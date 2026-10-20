-- Conta registros de recebimento, não volumes; divergências aguardam conferência e não penalizam o morador.
create or replace function portal_private.situacao_avisos(p_morador_id integer)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('pendencias_antigas',count(*),'avisos_bloqueados',count(*)>=10)
 from public.encomendas e
 where e.morador_id=p_morador_id and e.status='DISPONÍVEL' and e.criado_em<now()-interval '10 days';
$$;
revoke all on function portal_private.situacao_avisos(integer) from public,anon,authenticated;
grant execute on function portal_private.situacao_avisos(integer) to service_role;
create index if not exists encomendas_avisos_pendentes_idx on public.encomendas(morador_id,criado_em) where status='DISPONÍVEL';

CREATE OR REPLACE FUNCTION portal_private.emitir_link(p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare enc public.encomendas%rowtype;t text; situacao jsonb; destino integer;
begin
 select e.morador_id into destino from public.encomendas e where e.id=p_id;
 perform 1 from public.moradores m where m.id=destino and m.ativo for update;
 if not found then raise exception 'Morador não está ativo.';end if;
 select e.* into enc from public.encomendas e join public.moradores m on m.id=e.morador_id where e.id=p_id and e.status='DISPONÍVEL' and m.ativo;
 if not found then raise exception 'Encomenda não disponível para aviso.';end if;
 situacao:=portal_private.situacao_avisos(enc.morador_id);
 if (situacao->>'avisos_bloqueados')::boolean then
   return to_jsonb(enc)||situacao||jsonb_build_object('mensagem_suspensao',
     'Há '||(situacao->>'pendencias_antigas')||' encomendas registradas há mais de 10 dias sem confirmação de retirada para sua unidade. Os avisos de novas encomendas estão suspensos até a regularização. Se já retirou, confirme a baixa pelos links recebidos ou procure a portaria para conferir as pendências. Os avisos voltam quando restarem menos de 10 encomendas nessa condição.');
 end if;
 t:=encode(extensions.gen_random_bytes(32),'hex');
 update portal_private.links_encomendas set revogado=true where encomenda_id=enc.id and not revogado;
 insert into portal_private.links_encomendas(token_hash,encomenda_id,expira_em) values(encode(extensions.digest(t,'sha256'),'hex'),enc.id,now()+interval '30 days');
 return to_jsonb(enc)||jsonb_build_object('token',t)||situacao;
end $function$;

CREATE OR REPLACE FUNCTION portal_private.gateway(p_acao text, p_dados jsonb DEFAULT '{}'::jsonb, p_sessao text DEFAULT NULL::text, p_token text DEFAULT NULL::text, p_origem text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess portal_private.sessoes_portaria%rowtype; link portal_private.links_encomendas%rowtype;
 morador public.moradores%rowtype; enc public.encomendas%rowtype; segredo text; t text; hashed text;
 resultado jsonb; rate integer; b text;a text;n text;tel text;
begin
 -- O gateway HTTP é o único chamador (service_role). Não aceita SQL nem papel no payload.
 if p_acao in ('entrar','solicitar_cadastro','ver_encomenda','confirmar_retirada','informar_engano') then
   insert into portal_private.limites_portal(chave,inicio,tentativas)
     values(p_acao||':'||p_origem,now(),1)
     on conflict(chave) do update set
      tentativas=case when portal_private.limites_portal.inicio<now()-interval '15 minutes' then 1 else portal_private.limites_portal.tentativas+1 end,
      inicio=case when portal_private.limites_portal.inicio<now()-interval '15 minutes' then now() else portal_private.limites_portal.inicio end
      returning tentativas into rate;
   if rate>(case when p_acao='entrar' then 10 when p_acao='solicitar_cadastro' then 20 else 100 end) then
      return jsonb_build_object('erro','Muitas tentativas. Aguarde alguns minutos.','codigo',429);
   end if;
 end if;
 if p_acao='entrar' then
   select senha_hash into segredo from portal_private.acesso_portaria where chave;
   if segredo is null then return jsonb_build_object('erro','A administração precisa configurar a senha da portaria.','codigo',503);end if;
   if length(coalesce(p_dados->>'senha',''))>72 or segredo<>extensions.crypt(coalesce(p_dados->>'senha',''),segredo) then
      return jsonb_build_object('erro','Senha incorreta. Tente novamente.','codigo',401);
   end if;
   t:=encode(extensions.gen_random_bytes(32),'hex');
   insert into portal_private.sessoes_portaria(token_hash,expira_em) values(encode(extensions.digest(t,'sha256'),'hex'),now()+interval '12 hours');
   return jsonb_build_object('sessao',t,'expira_em',now()+interval '12 hours');
 elsif p_acao='solicitar_cadastro' then
   b:=upper(trim(p_dados->>'bloco'));a:=lpad(trim(p_dados->>'apartamento'),2,'0');n:=trim(p_dados->>'nome');
   tel:=regexp_replace(coalesce(p_dados->>'whatsapp',''),'[^0-9]','','g');if length(tel) in (10,11) then tel:='55'||tel;end if;
   if b is null or b !~ '^[A-F]$' or a is null or a !~ '^[0-9]{2}$' or a::int not between 1 and 74 or n is null or length(n) not between 3 and 120 or tel !~ '^55[1-9][0-9][0-9]{8,9}$' then
      return jsonb_build_object('erro','Confira nome, unidade e WhatsApp com DDD.','codigo',400);
   end if;
   insert into portal_private.pedidos(bloco,apartamento,nome,whatsapp) values(b,a,upper(n),tel)
     on conflict(bloco,apartamento,whatsapp) where status='PENDENTE' do update set nome=excluded.nome,criado_em=now();
   return jsonb_build_object('ok',true,'mensagem','Solicitação enviada para conferência da portaria.');
 elsif p_acao in ('ver_encomenda','confirmar_retirada','informar_engano') then
   if coalesce(p_token,'') !~ '^[a-f0-9]{64}$' then return jsonb_build_object('erro','Link inválido ou expirado. Solicite novo aviso à portaria.','codigo',403);end if;
   select * into link from portal_private.links_encomendas where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and expira_em>now() and not revogado for update;
   if not found then return jsonb_build_object('erro','Link inválido ou expirado. Solicite novo aviso à portaria.','codigo',403);end if;
   -- A saída e o recebimento bloqueiam o mesmo morador antes de operar encomendas.
   select m.* into morador from public.moradores m join public.encomendas e on e.morador_id=m.id where e.id=link.encomenda_id for update of m;
   if not found or not morador.ativo then return jsonb_build_object('erro','Este link não está mais disponível. Procure a portaria.','codigo',403);end if;
   select * into enc from public.encomendas where id=link.encomenda_id for update;
   if p_acao<>'ver_encomenda' and enc.status='DISPONÍVEL' then
      update public.encomendas set status=case when p_acao='informar_engano' then 'DIVERGÊNCIA' else 'ENTREGUE' end,
        baixado_pela=case when p_acao='informar_engano' then 'ENGANO' else 'MORADOR' end,
        baixado_em=case when p_acao='informar_engano' then null else now() end where id=enc.id returning * into enc;
      insert into portal_private.auditoria(autor,acao,entidade_id) values(substring(link.token_hash,1,32)::uuid,p_acao,enc.id);
   end if;
   if enc.status='ENTREGUE' then return jsonb_build_object('status','ENTREGUE');end if;
   return jsonb_build_object('id',enc.id,'quantidade',enc.quantidade,'status',enc.status,'nome',morador.nome,'bloco',morador.bloco,'apartamento',morador.apartamento);
 end if;
 if coalesce(p_sessao,'') !~ '^[a-f0-9]{64}$' then return jsonb_build_object('erro','Entre com a senha da portaria.','codigo',401);end if;
 select * into sess from portal_private.sessoes_portaria where token_hash=encode(extensions.digest(p_sessao,'sha256'),'hex') and expira_em>now() and not revogada;
 if not found then return jsonb_build_object('erro','Sessão encerrada. Entre novamente.','codigo',401);end if;
 if p_acao='sair' then update portal_private.sessoes_portaria set revogada=true where id=sess.id;return jsonb_build_object('ok',true);
 elsif p_acao='sessao' then return jsonb_build_object('ok',true);
 elsif p_acao in ('registrar','avisar') then
   if p_acao='registrar' then
      resultado:=portal_private.operar_portaria(sess.id,'registrar',p_dados);
      select * into enc from public.encomendas where id=(resultado->>'id')::int;
   else
      select * into enc from public.encomendas where id=(p_dados->>'id')::int;
   end if;
   if enc.id is null or enc.status<>'DISPONÍVEL' then return jsonb_build_object('erro','Encomenda não disponível para aviso.','codigo',400);end if;
   if not exists(select 1 from public.moradores where id=enc.morador_id and ativo) then return jsonb_build_object('erro','Morador não está ativo.','codigo',400);end if;
   return portal_private.emitir_link(enc.id);
 end if;
 return portal_private.operar_portaria(sess.id,p_acao,p_dados);
end $function$;

CREATE OR REPLACE FUNCTION portal_private.operar_portaria(p_autor uuid, p_acao text, p_dados jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=p_autor; m public.moradores%rowtype; enc public.encomendas%rowtype;
 solicitacao portal_private.pedidos%rowtype; resultado jsonb; qtd integer; pedido uuid; n text;
begin
 if p_acao='moradores' then
   select coalesce(jsonb_agg(to_jsonb(r)||portal_private.situacao_avisos(r.id) order by r.bloco,r.apartamento,r.nome),'[]') into resultado from public.moradores r where r.ativo;
   return resultado;
 elsif p_acao='pendencias' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em,x.id),'[]') into resultado from (
    select e.*,dst.nome,dst.bloco,dst.apartamento,dst.whatsapp,dst.ativo as morador_ativo,(portal_private.situacao_avisos(dst.id)->>'pendencias_antigas')::int as pendencias_antigas,(portal_private.situacao_avisos(dst.id)->>'avisos_bloqueados')::boolean as avisos_bloqueados from public.encomendas e
    left join public.moradores dst on dst.id=e.morador_id where e.status in ('DISPONÍVEL','DIVERGÊNCIA')
   ) x;return resultado;
 elsif p_acao='registrar' then
   select * into m from public.moradores where id=(p_dados->>'morador_id')::int for update;
   if not found or not m.ativo then raise exception 'Morador não está ativo. Atualize os cadastros.'; end if;
   qtd:=(p_dados->>'quantidade')::int; pedido:=(p_dados->>'operacao_id')::uuid;
   if qtd is null or qtd not between 1 and 99 or pedido is null then raise exception 'Informe de 1 a 99 volumes.'; end if;
   select * into enc from public.encomendas where operacao_id=pedido;
   if found then
     if enc.morador_id<>m.id or enc.quantidade<>qtd then raise exception 'Operação já utilizada. Atualize a página.'; end if;
     return to_jsonb(enc);
   end if;
   insert into public.encomendas(morador_id,quantidade,registrado_por,operacao_id,status,observacao)
    values(m.id,qtd,null,pedido,'DISPONÍVEL',left(trim(p_dados->>'observacao'),500)) returning * into enc;
   insert into portal_private.auditoria(autor,acao,entidade_id) values(uid,p_acao,enc.id);
   return to_jsonb(enc);
 elsif p_acao in ('baixar','devolver','resolver_divergencia') then
   select r.* into m from public.moradores r join public.encomendas e on e.morador_id=r.id where e.id=(p_dados->>'id')::int for update of r;
   select * into enc from public.encomendas where id=(p_dados->>'id')::int for update;
   if not found then raise exception 'Encomenda não encontrada.'; end if;
   if enc.status not in ('DISPONÍVEL','DIVERGÊNCIA') then return jsonb_build_object('ok',true,'ja_processada',true); end if;
   n:=trim(p_dados->>'recebedor');
   n:=nullif(n,''); if p_acao='baixar' and n is not null and length(n) not between 3 and 120 then raise exception 'Confira o nome de quem retirou.';end if;
   if p_acao='devolver' and length(coalesce(trim(p_dados->>'observacao'),''))<5 then raise exception 'Informe o motivo da devolução.'; end if;
   update public.encomendas set
    status=case p_acao when 'baixar' then 'ENTREGUE' when 'devolver' then 'DEVOLVIDA' else 'DISPONÍVEL' end,
    baixado_pela=case when p_acao='resolver_divergencia' then null else 'PORTARIA' end,
    baixado_em=case when p_acao='resolver_divergencia' then null else now() end,
    recebedor=case when p_acao='baixar' then n else null end,
    observacao=case when p_acao='devolver' then left(trim(p_dados->>'observacao'),500) else observacao end
    where id=enc.id;
   insert into portal_private.auditoria(autor,acao,entidade_id,detalhes) values(uid,p_acao,enc.id,jsonb_build_object('status_anterior',enc.status));
   return jsonb_build_object('ok',true);
 elsif p_acao='mudar_morador' then
   select * into m from public.moradores where id=(p_dados->>'id')::int for update;
   if not found or not m.ativo then raise exception 'Cadastro já está inativo. Atualize a lista.'; end if;
   if upper(trim(p_dados->>'confirmacao')) is distinct from (upper(m.bloco)||'-'||m.apartamento) then raise exception 'Digite a unidade corretamente para confirmar.'; end if;
   if exists(select 1 from public.encomendas where morador_id=m.id and status in ('DISPONÍVEL','DIVERGÊNCIA')) then
    raise exception 'Há encomendas pendentes. Registre a retirada ou devolução antes da mudança.'; end if;
   update public.moradores set ativo=false,mudou_em=now() where id=m.id;
   -- Não reutilizar o ID do antigo morador nem transferir suas encomendas ao próximo.
   update portal_private.solicitacoes set status='CANCELADO',resolvido_em=now(),resolvido_por=uid where user_id=m.user_id and status='PENDENTE';
   insert into portal_private.auditoria(autor,acao,entidade_id,detalhes) values(uid,p_acao,m.id,jsonb_build_object('unidade',m.bloco||'-'||m.apartamento));
   return jsonb_build_object('ok',true,'unidade_liberada',true);
 elsif p_acao='solicitacoes' then
 select coalesce(jsonb_agg(to_jsonb(s) order by s.criado_em),'[]') into resultado from portal_private.pedidos s where status='PENDENTE';return resultado;
 elsif p_acao in ('aprovar','rejeitar') then
 select * into solicitacao from portal_private.pedidos where id=(p_dados->>'id')::bigint for update;
 if not found or solicitacao.status<>'PENDENTE' then raise exception 'Solicitação já processada.';end if;
 perform pg_advisory_xact_lock(hashtext(solicitacao.bloco||'-'||solicitacao.apartamento));
 if p_acao='aprovar' then
   if exists(select 1 from public.moradores where ativo and upper(trim(bloco))=solicitacao.bloco and lpad(trim(apartamento),2,'0')=solicitacao.apartamento) then
      raise exception 'A unidade já tem cadastro ativo. Se o morador mudou, registre a mudança antes de aprovar o novo.';
   end if;
   insert into public.moradores(bloco,apartamento,nome,whatsapp) values(solicitacao.bloco,solicitacao.apartamento,solicitacao.nome,solicitacao.whatsapp);
 end if;
 update portal_private.pedidos set status=case when p_acao='aprovar' then 'APROVADO' else 'REJEITADO' end,resolvido_em=now(),resolvido_por=uid where id=solicitacao.id;
 insert into portal_private.auditoria(autor,acao,entidade_id) values(uid,p_acao,solicitacao.id);
 return jsonb_build_object('ok',true);
 elsif p_acao='historico' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em desc,x.id desc),'[]') into resultado from (
    select e.*,dst.nome,dst.bloco,dst.apartamento,dst.ativo as morador_ativo from public.encomendas e left join public.moradores dst on dst.id=e.morador_id
    order by e.criado_em desc,e.id desc limit 500 offset greatest(0,coalesce((p_dados->>'offset')::int,0))
   ) x;return resultado;
 elsif p_acao='ex_moradores' then
   select coalesce(jsonb_agg(to_jsonb(r) order by r.mudou_em desc),'[]') into resultado from public.moradores r where not r.ativo;return resultado;
 end if;

 raise exception 'Operação inválida.';
end $function$;
