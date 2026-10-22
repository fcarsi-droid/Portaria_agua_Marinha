begin;
do $test$
declare mid int; outro int; antigo int; novo int; admin_id uuid; admin_session uuid; s text:=encode(extensions.gen_random_bytes(32),'hex'); exp text:=encode(extensions.gen_random_bytes(32),'hex');rev text:=encode(extensions.gen_random_bytes(32),'hex');t text;r jsonb;op uuid:=gen_random_uuid(); n int; 
begin
  insert into portal_private.sessoes_portaria(token_hash,expira_em) values(encode(extensions.digest(s,'sha256'),'hex'),now()+interval '1 hour');
  insert into portal_private.sessoes_portaria(token_hash,expira_em) values(encode(extensions.digest(exp,'sha256'),'hex'),now()-interval '1 hour');
  insert into portal_private.sessoes_portaria(token_hash,expira_em,revogada) values(encode(extensions.digest(rev,'sha256'),'hex'),now()+interval '1 hour',true);
  r:=public.portal_gateway('sessao','{}',s);if r->>'ok'<>'true' then raise exception 'Sessão válida rejeitada';end if;
  if not exists(select 1 from portal_private.sessoes_portaria where token_hash=encode(extensions.digest(s,'sha256'),'hex') and expira_em>now()+interval '29 days') then raise exception 'Não renovou a sessão';end if;
  r:=public.portal_gateway('sessao','{}',exp);if r->>'codigo'<>'401' then raise exception 'Sessão expirada reativada';end if;
  r:=public.portal_gateway('sessao','{}',rev);if r->>'codigo'<>'401' then raise exception 'Sessão revogada reativada';end if;
  insert into public.moradores(bloco,apartamento,nome,whatsapp) values('TESTE-'||gen_random_uuid(),'99','TESTE REGRA','5519999991234') returning id into mid;
  insert into public.moradores(bloco,apartamento,nome,whatsapp) values('TESTE-'||gen_random_uuid(),'99','TESTE OUTRO','5519999991234') returning id into outro;
  -- Dez pendentes, mesmo antigas e com mais volumes, ainda permitem aviso.
  insert into public.encomendas(morador_id,quantidade,criado_em,status) select mid,2,now()-interval '5 days','DISPONÍVEL' from generate_series(1,10);
  select min(id) into antigo from public.encomendas where morador_id=mid;
  r:=public.portal_gateway('avisar',jsonb_build_object('id',antigo),s);t:=r->>'token';
  if t is null or (r->>'avisos_bloqueados')::boolean then raise exception 'Bloqueou com dez';end if;
  -- A décima primeira é nova: todas não precisam ter quatro dias.
  r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',1,'operacao_id',op),s);novo:=(r->>'id')::int;
  if novo is null or r ? 'token' or r->>'codigo'<>'409' or not (r->>'avisos_bloqueados')::boolean or r->>'remessas_sem_baixa'<>'11' then raise exception 'Não bloqueou o aviso da décima primeira';end if;
  r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',1,'operacao_id',op),s);
  select count(*) into n from public.encomendas where operacao_id=op;if n<>1 then raise exception 'Registro duplicado em retry';end if;
  -- Sem quatro dias do primeiro aviso, onze ainda não bloqueiam.
  update public.encomendas set criado_em=now()-interval '3 days 23 hours' where morador_id=mid;
  r:=public.portal_gateway('avisar',jsonb_build_object('id',novo),s);
  if r->>'token' is null or (r->>'avisos_bloqueados')::boolean then raise exception 'Bloqueou antes de quatro dias';end if;
  update public.encomendas set criado_em=now()-interval '4 days' where id=antigo;
  r:=public.portal_gateway('avisar',jsonb_build_object('id',novo),s);
  if not (r->>'avisos_bloqueados')::boolean or r ? 'token' then raise exception 'Não bloqueou aos quatro dias';end if;
  -- Admin usa o mesmo bloqueio, sem mudar sua autenticação.
  select u.id into admin_id from auth.users u join portal_private.equipe e on e.user_id=u.id where e.papel='admin' and e.ativo and u.email_confirmed_at is not null order by u.created_at limit 1;
  select a.id into admin_session from auth.sessions a where a.user_id=admin_id and(a.not_after is null or a.not_after>now()) order by a.created_at desc limit 1;
  if admin_session is not null then
   perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'session_id',admin_session)::text,true);
   r:=public.admin_operacao('avisar',jsonb_build_object('id',novo));
   if not (r->>'avisos_bloqueados')::boolean or r ? 'token' then raise exception 'Administrador contornou o bloqueio';end if;
  end if;
  r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',outro,'quantidade',1,'operacao_id',gen_random_uuid()),s);
  if r->>'token' is null then raise exception 'Afetou outro morador';end if;
  -- Link antigo continua válido e a baixa do morador regulariza a situação.
  r:=public.portal_gateway('confirmar_retirada','{}',null,t,'teste-regra');
  if r->>'status'<>'ENTREGUE' then raise exception 'Bloqueou regularização pelo morador';end if;
  r:=public.portal_gateway('avisar',jsonb_build_object('id',novo),s);
  if r->>'token' is null or (r->>'avisos_bloqueados')::boolean then raise exception 'Não desbloqueou com dez remessas';end if;
  r:=public.portal_gateway('aprovar','{}',s);if r->>'codigo'<>'403' then raise exception 'Portaria pode aprovar';end if;
  perform public.portal_gateway('sair','{}',s);r:=public.portal_gateway('sessao','{}',s);if r->>'codigo'<>'401' then raise exception 'Logout não revogou sessão';end if;
  if has_function_privilege('anon','portal_private.situacao_avisos(integer)','execute') or has_function_privilege('authenticated','portal_private.situacao_avisos(integer)','execute') then raise exception 'Função privada exposta';end if;
end $test$;

select 'OK: dez não bloqueiam; décima primeira bloqueada com primeiro aviso de quatro dias; sessões renovadas, expiradas/revogadas recusadas; links e regularização preservados' as resultado;
rollback;