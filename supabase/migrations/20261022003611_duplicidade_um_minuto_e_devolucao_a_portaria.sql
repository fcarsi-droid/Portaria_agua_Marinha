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
    select e.*,dst.nome,dst.bloco,dst.apartamento,dst.whatsapp,dst.ativo as morador_ativo,(portal_private.situacao_avisos(dst.id)->>'remessas_sem_baixa')::int as remessas_sem_baixa,(portal_private.situacao_avisos(dst.id)->>'avisos_bloqueados')::boolean as avisos_bloqueados from public.encomendas e
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
     return to_jsonb(enc)||portal_private.situacao_avisos(m.id)||jsonb_build_object('registro_existente',true,'codigo',409,'erro','Esta operação já foi registrada. Use o registro existente para reenviar o aviso.');
   end if;
   select * into enc from public.encomendas where morador_id=m.id and quantidade=qtd and status in ('DISPONÍVEL','DIVERGÊNCIA') and criado_em>=now()-interval '1 minute' order by criado_em desc,id desc limit 1 for update;
   if found and coalesce((p_dados->>'confirmar_nova_remessa_id')::int,0)<>enc.id then
    return to_jsonb(enc)||portal_private.situacao_avisos(m.id)||jsonb_build_object('registro_existente',true,'codigo',409,'erro','Já existe um registro recente para este morador e esta quantidade. Reenvie o aviso ou confirme que é outra encomenda.');
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
   if p_acao='devolver' and enc.status<>'DIVERGÊNCIA' then raise exception 'Esta opção é para encomendas que o morador informou não serem dele.'; end if;
   update public.encomendas set
    status=case p_acao when 'baixar' then 'ENTREGUE' when 'devolver' then 'DEVOLVIDA' else 'DISPONÍVEL' end,
    baixado_pela=case when p_acao='resolver_divergencia' then null else 'PORTARIA' end,
    baixado_em=case when p_acao='resolver_divergencia' then null else now() end,
    recebedor=case when p_acao='baixar' then n else null end,
    observacao=case when p_acao='devolver' then left(concat_ws(E'\n',nullif(observacao,''),'Devolvida à portaria após destinatário informar que não é sua. Registro encerrado para novo cadastro no destinatário correto.'),500) else observacao end
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

