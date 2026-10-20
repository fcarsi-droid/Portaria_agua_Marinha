begin;
do $test$
declare mid int; other_mid int; eid int; boundary int; latest int; r jsonb; token text; existing_token text; session_token text:=repeat('d',64); total int; op uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); admin_session uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,email_confirmed_at) values(admin_id,'suspensao@example.invalid',now());
 insert into auth.sessions(id,user_id) values(admin_session,admin_id);
 insert into portal_private.equipe(user_id,papel) values(admin_id,'admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'session_id',admin_session)::text,true);
 insert into portal_private.sessoes_portaria(token_hash,expira_em) values(encode(extensions.digest(session_token,'sha256'),'hex'),now()+interval '1 hour');
 insert into public.moradores(bloco,apartamento,nome,whatsapp) values('F','74','TESTE SUSPENSAO','5519999991234') returning id into mid;
 insert into public.moradores(bloco,apartamento,nome,whatsapp) values('F','73','TESTE ISOLAMENTO','5519999991234') returning id into other_mid;
 -- Nove recebimentos antigos, mesmo com muitos volumes, não suspendem.
 insert into public.encomendas(morador_id,quantidade,criado_em,status) select mid,2,now()-interval '11 days','DISPONÍVEL' from generate_series(1,9);
 insert into public.encomendas(morador_id,quantidade,criado_em,status) values(mid,1,now()-interval '10 days','DISPONÍVEL') returning id into boundary;
 insert into public.encomendas(morador_id,quantidade,criado_em,status) select mid,1,now()-interval '20 days',s from unnest(array['ENTREGUE','DEVOLVIDA','DIVERGÊNCIA']) s;
 r:=portal_private.situacao_avisos(mid);
 if (r->>'pendencias_antigas')::int<>9 or (r->>'avisos_bloqueados')::boolean then raise exception 'Falhou limite nove, dez dias exatos ou filtro por status';end if;
 select min(id) into eid from public.encomendas where morador_id=mid and status='DISPONÍVEL';
 r:=public.portal_gateway('avisar',jsonb_build_object('id',eid),session_token);existing_token:=r->>'token';
 if existing_token is null then raise exception 'Bloqueou antes do limite';end if;
 update public.encomendas set criado_em=now()-interval '10 days 1 second' where id=boundary;
 r:=public.portal_gateway('avisar',jsonb_build_object('id',eid),session_token);
 if not (r->>'avisos_bloqueados')::boolean or r ? 'token' or r->>'mensagem_suspensao' is null then raise exception 'Aviso normal não foi bloqueado ao atingir dez';end if;
 r:=public.admin_operacao('avisar',jsonb_build_object('id',eid));
 if not (r->>'avisos_bloqueados')::boolean or r ? 'token' then raise exception 'Administrador contornou bloqueio';end if;
 r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',3,'operacao_id',op),session_token);latest:=(r->>'id')::int;
 if latest is null or not (r->>'avisos_bloqueados')::boolean or r ? 'token' then raise exception 'Registro bloqueado ou aviso liberado durante suspensão';end if;
 r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',3,'operacao_id',op),session_token);
 select count(*) into total from public.encomendas where operacao_id=op;
 if total<>1 or (r->>'id')::int<>latest then raise exception 'Retry duplicou registro suspenso';end if;
 r:=public.portal_gateway('moradores','{}',session_token);
 if not exists(select 1 from jsonb_array_elements(r) x where (x->>'id')::int=mid and (x->>'avisos_bloqueados')::boolean and (x->>'pendencias_antigas')::int=10) then raise exception 'Morador sem sinalização';end if;
 r:=public.portal_gateway('pendencias','{}',session_token);
 if not exists(select 1 from jsonb_array_elements(r) x where (x->>'id')::int=latest and (x->>'avisos_bloqueados')::boolean) then raise exception 'Pendência sem sinalização';end if;
 -- Outra unidade continua recebendo normalmente.
 r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',other_mid,'quantidade',1,'operacao_id',gen_random_uuid()),session_token);
 if r->>'token' is null or (r->>'avisos_bloqueados')::boolean then raise exception 'Suspensão atingiu outro morador';end if;
 -- Links emitidos antes da suspensão ainda permitem a baixa, sem bloquear a regularização.
 r:=public.portal_gateway('confirmar_retirada','{}',null,existing_token,'teste-suspensao');
 if r->>'status'<>'ENTREGUE' then raise exception 'Suspensão bloqueou baixa pelo morador';end if;
 r:=portal_private.situacao_avisos(mid);
 if (r->>'pendencias_antigas')::int<>9 or (r->>'avisos_bloqueados')::boolean then raise exception 'Não desbloqueou após regularização';end if;
 r:=public.portal_gateway('avisar',jsonb_build_object('id',latest),session_token);
 if r->>'token' is null or (r->>'avisos_bloqueados')::boolean then raise exception 'Não voltou a emitir avisos';end if;
 -- Portaria também pode dar baixa durante suspensão.
 update public.encomendas set status='DISPONÍVEL',baixado_em=null where id=eid;
 perform public.portal_gateway('baixar',jsonb_build_object('id',boundary),session_token);
 r:=portal_private.situacao_avisos(mid);
 if (r->>'avisos_bloqueados')::boolean then raise exception 'Baixa da portaria não desbloqueou';end if;
 if has_function_privilege('anon','portal_private.situacao_avisos(integer)','execute') or has_function_privilege('authenticated','portal_private.situacao_avisos(integer)','execute') then raise exception 'Contagem privada exposta';end if;
end $test$;
select 'OK: limites 9/10, idade estrita, status, isolamento, suspensão no servidor e admin, registro idempotente, avisos sem token, baixa e desbloqueio' as resultado;
rollback;
