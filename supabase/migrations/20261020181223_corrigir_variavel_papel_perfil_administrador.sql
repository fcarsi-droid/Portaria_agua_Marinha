-- Aplicada no Supabase; preserva validação de identidade e sessão.
-- Validada com perfil admin e consultas do painel, em transação revertida.
CREATE OR REPLACE FUNCTION portal_private.executar(p_acao text, p_dados jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 uid uuid := auth.uid(); v_papel text; email_verificado text; sessao uuid;
 m public.moradores%rowtype; enc public.encomendas%rowtype; sol portal_private.solicitacoes%rowtype;
 resultado jsonb; b text; a text; n text; tel text; qtd integer; pedido uuid; alvo uuid; contador integer;
begin
 if uid is null then raise exception 'Entre na sua conta para continuar.' using errcode='42501'; end if;
 sessao := nullif(auth.jwt()->>'session_id','')::uuid;
 if sessao is null or not exists(select 1 from auth.sessions where id=sessao and user_id=uid and (not_after is null or not_after>now())) then
   raise exception 'Sua sessão expirou. Entre novamente.' using errcode='42501';
 end if;
 select lower(email) into email_verificado from auth.users where id=uid and email_confirmed_at is not null and (banned_until is null or banned_until<now());
 if email_verificado is null then raise exception 'Confirme seu e-mail antes de continuar.' using errcode='42501'; end if;
 -- O bootstrap só ocorre uma vez, para o e-mail escolhido pelo proprietário e verificado pelo Auth.
 if exists(select 1 from portal_private.administrador_inicial where email=email_verificado and ativado_em is null) then
   perform pg_advisory_xact_lock(873401);
   if not exists(select 1 from portal_private.equipe e where e.papel='admin') then
     insert into portal_private.equipe(user_id,papel) values(uid,'admin') on conflict do nothing;
     update portal_private.administrador_inicial set ativado_em=now() where email=email_verificado;
   end if;
 end if;
 select e.papel into v_papel from portal_private.equipe e where user_id=uid and ativo;
 if p_acao='perfil' then
   return jsonb_build_object('papel',coalesce(v_papel,'morador'),'email',email_verificado,
     'morador',(select to_jsonb(r) from public.moradores r where user_id=uid and ativo),
     'solicitacao',(select to_jsonb(s) from portal_private.solicitacoes s where user_id=uid order by id desc limit 1));
 elsif p_acao='solicitar_cadastro' then
   if exists(select 1 from public.moradores where user_id=uid and ativo) then raise exception 'Você já possui cadastro ativo.'; end if;
   b:=upper(trim(p_dados->>'bloco')); a:=lpad(trim(p_dados->>'apartamento'),2,'0');
   n:=trim(p_dados->>'nome'); tel:=regexp_replace(coalesce(p_dados->>'whatsapp',''),'[^0-9]','','g');
   if length(tel) in (10,11) then tel:='55'||tel; end if;
   if b is null or b !~ '^[A-F]$' or a is null or a !~ '^[0-9]{2}$' or a::int not between 1 and 74
      or n is null or length(n) not between 3 and 120 or tel !~ '^55[1-9][0-9][0-9]{8,9}$' then raise exception 'Confira nome, bloco, apartamento e WhatsApp com DDD.'; end if;
   insert into portal_private.solicitacoes(user_id,bloco,apartamento,nome,whatsapp) values(uid,b,a,upper(n),tel)
   on conflict(user_id) where status='PENDENTE' do update set bloco=excluded.bloco,apartamento=excluded.apartamento,nome=excluded.nome,whatsapp=excluded.whatsapp,criado_em=now();
   return jsonb_build_object('ok',true);
 elsif p_acao='minhas_encomendas' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em desc,x.id desc),'[]') into resultado from (
    select e.id,e.quantidade,e.criado_em,e.status,e.baixado_em,e.baixado_pela,e.recebedor,e.observacao,dst.nome,dst.bloco,dst.apartamento
    from public.encomendas e join public.moradores dst on dst.id=e.morador_id
    where dst.user_id=uid and dst.ativo order by e.criado_em desc,e.id desc limit 300
   ) x; return resultado;
 elsif p_acao in ('confirmar_retirada','informar_engano') then
   -- Mesma ordem de bloqueio usada na saída/registro: primeiro morador, depois encomenda.
   select r.* into m from public.moradores r join public.encomendas e on e.morador_id=r.id where e.id=(p_dados->>'id')::int for update of r;
   if not found or not m.ativo or m.user_id is distinct from uid then raise exception 'Encomenda indisponível para sua conta.' using errcode='42501'; end if;
   select * into enc from public.encomendas where id=(p_dados->>'id')::int for update;
   if enc.status<>'DISPONÍVEL' then return jsonb_build_object('ok',true,'ja_processada',true); end if;
   update public.encomendas set status=case when p_acao='informar_engano' then 'DIVERGÊNCIA' else 'ENTREGUE' end,
     baixado_pela=case when p_acao='informar_engano' then 'ENGANO' else 'MORADOR' end,
     baixado_em=case when p_acao='informar_engano' then null else now() end,recebedor=case when p_acao='confirmar_retirada' then m.nome else null end where id=enc.id;
   insert into portal_private.auditoria(autor,acao,entidade_id) values(uid,p_acao,enc.id);
   return jsonb_build_object('ok',true);
 end if;
 if v_papel is null then raise exception 'Ação permitida somente à portaria.' using errcode='42501'; end if;
 if p_acao='moradores' then
   select coalesce(jsonb_agg(to_jsonb(r) order by r.bloco,r.apartamento,r.nome),'[]') into resultado from public.moradores r where r.ativo;
   return resultado;
 elsif p_acao='pendencias' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em,x.id),'[]') into resultado from (
    select e.*,dst.nome,dst.bloco,dst.apartamento,dst.whatsapp,dst.ativo as morador_ativo from public.encomendas e
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
    values(m.id,qtd,uid,pedido,'DISPONÍVEL',left(trim(p_dados->>'observacao'),500)) returning * into enc;
   insert into portal_private.auditoria(autor,acao,entidade_id) values(uid,p_acao,enc.id);
   return to_jsonb(enc);
 elsif p_acao in ('baixar','devolver','resolver_divergencia') then
   select r.* into m from public.moradores r join public.encomendas e on e.morador_id=r.id where e.id=(p_dados->>'id')::int for update of r;
   select * into enc from public.encomendas where id=(p_dados->>'id')::int for update;
   if not found then raise exception 'Encomenda não encontrada.'; end if;
   if enc.status not in ('DISPONÍVEL','DIVERGÊNCIA') then return jsonb_build_object('ok',true,'ja_processada',true); end if;
   n:=trim(p_dados->>'recebedor');
   if p_acao='baixar' and (n is null or length(n) not between 3 and 120) then raise exception 'Informe o nome de quem retirou.'; end if;
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
   select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em),'[]') into resultado from (
    select s.*,u.email,(select count(*) from public.moradores r where r.ativo and upper(trim(r.bloco))=s.bloco and lpad(trim(r.apartamento),2,'0')=s.apartamento) as unidade_ocupada
    from portal_private.solicitacoes s join auth.users u on u.id=s.user_id where s.status='PENDENTE'
   ) x;return resultado;
 elsif p_acao in ('aprovar','rejeitar') then
   select * into sol from portal_private.solicitacoes where id=(p_dados->>'id')::bigint for update;
   if not found or sol.status<>'PENDENTE' then raise exception 'Solicitação já foi processada.'; end if;
   perform pg_advisory_xact_lock(hashtext(sol.bloco||'-'||sol.apartamento));
   if p_acao='aprovar' then
    if exists(select 1 from public.moradores where user_id=sol.user_id and ativo) then raise exception 'Usuário já vinculado a outra unidade.'; end if;
    select * into m from public.moradores where upper(trim(bloco))=sol.bloco and lpad(trim(apartamento),2,'0')=sol.apartamento and ativo for update;
    if found then
     -- Só vincula cadastro legado se a portaria confirmou que é a mesma pessoa.
     if m.user_id is not null then raise exception 'Apartamento já possui acesso ativo. Registre a mudança antes de aprovar outro morador.'; end if;
     if coalesce((p_dados->>'mesma_pessoa')::boolean,false) is not true then raise exception 'Confirme se é o mesmo morador do cadastro existente. Se houve mudança, libere o apartamento primeiro.'; end if;
     update public.moradores set user_id=sol.user_id,whatsapp=sol.whatsapp where id=m.id;
    else
     insert into public.moradores(bloco,apartamento,nome,whatsapp,user_id) values(sol.bloco,sol.apartamento,sol.nome,sol.whatsapp,sol.user_id);
    end if;
   end if;
   update portal_private.solicitacoes set status=case when p_acao='aprovar' then 'APROVADO' else 'REJEITADO' end,resolvido_em=now(),resolvido_por=uid where id=sol.id;
   insert into portal_private.auditoria(autor,acao,entidade_id) values(uid,p_acao,sol.id);
   return jsonb_build_object('ok',true);
 elsif p_acao='historico' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em desc,x.id desc),'[]') into resultado from (
    select e.*,dst.nome,dst.bloco,dst.apartamento,dst.ativo as morador_ativo from public.encomendas e left join public.moradores dst on dst.id=e.morador_id
    order by e.criado_em desc,e.id desc limit 500 offset greatest(0,coalesce((p_dados->>'offset')::int,0))
   ) x;return resultado;
 elsif p_acao='ex_moradores' then
   select coalesce(jsonb_agg(to_jsonb(r) order by r.mudou_em desc),'[]') into resultado from public.moradores r where not r.ativo;return resultado;
 end if;
 if v_papel<>'admin' then raise exception 'Ação permitida somente ao administrador.' using errcode='42501'; end if;
 if p_acao='equipe' then
   select coalesce(jsonb_agg(jsonb_build_object('user_id',e.user_id,'email',u.email,'papel',e.papel,'ativo',e.ativo)),'[]') into resultado
   from portal_private.equipe e join auth.users u on u.id=e.user_id;return resultado;
 elsif p_acao='salvar_equipe' then
   if p_dados->>'papel' not in ('admin','portaria') then raise exception 'Papel inválido.'; end if;
   select id into alvo from auth.users where lower(email)=lower(trim(p_dados->>'email')) and email_confirmed_at is not null;
   if alvo is null then raise exception 'Essa pessoa deve criar e confirmar a conta primeiro.'; end if;
   if alvo=uid and (p_dados->>'papel'<>'admin' or not coalesce((p_dados->>'ativo')::boolean,true)) then raise exception 'Você não pode remover seu próprio acesso de administrador.'; end if;
   insert into portal_private.equipe(user_id,papel,ativo) values(alvo,p_dados->>'papel',coalesce((p_dados->>'ativo')::boolean,true))
    on conflict(user_id) do update set papel=excluded.papel,ativo=excluded.ativo;
   insert into portal_private.auditoria(autor,acao,detalhes) values(uid,p_acao,jsonb_build_object('alvo',alvo));
   return jsonb_build_object('ok',true);
 end if;
 raise exception 'Operação inválida.';
end $function$
