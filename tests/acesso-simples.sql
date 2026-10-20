
begin;
do $test$
declare admin_id uuid:=gen_random_uuid();admin_session uuid:=gen_random_uuid();senha text:='teste-local-12345';s text;t text;t2 text;
 mid integer;mid2 integer;eid integer;eid2 integer;pedido bigint; op uuid:=gen_random_uuid(); r jsonb;blocked boolean;
begin
 insert into auth.users(id,email,email_confirmed_at)values(admin_id,'teste-admin@example.invalid',now());
 insert into auth.sessions(id,user_id)values(admin_session,admin_id);
 insert into portal_private.equipe(user_id,papel)values(admin_id,'admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'session_id',admin_session)::text,true);
 perform public.admin_portaria(senha);
 if exists(select 1 from portal_private.acesso_portaria where senha_hash=senha) then raise exception 'Senha armazenada sem hash';end if;
 r:=public.portal_gateway('entrar',jsonb_build_object('senha','errada'),null,null,'ip-errado');
 if r->>'codigo'<>'401' then raise exception 'Senha errada aceita';end if;
 r:=public.portal_gateway('entrar',jsonb_build_object('senha',senha),null,null,'ip-correto');s:=r->>'sessao';
 if length(s)<>64 then raise exception 'Sessão inválida';end if;
 if exists(select 1 from portal_private.sessoes_portaria where token_hash=s) then raise exception 'Token de sessão em texto';end if;
 insert into public.moradores(bloco,apartamento,nome,whatsapp)values('A','01','ANTIGO TESTE','5519999991234')returning id into mid;
 insert into public.moradores(bloco,apartamento,nome,whatsapp)values('B','01','OUTRO TESTE','5519999991234')returning id into mid2;
 r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',2,'operacao_id',op),s);eid:=(r->>'id')::int;t:=r->>'token';
 r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',2,'operacao_id',op),s);
 if (r->>'id')::int<>eid then raise exception 'Registro duplicado';end if;
 -- Retry gera novo link e revoga o anterior.
 t2:=r->>'token';
 r:=public.portal_gateway('ver_encomenda','{}',null,t,'ip-link');
 if r->>'codigo'<>'403' then raise exception 'Link antigo permaneceu válido';end if;
 r:=public.portal_gateway('registrar',jsonb_build_object('morador_id',mid2,'quantidade',1,'operacao_id',gen_random_uuid()),s);eid2:=(r->>'id')::int;
 r:=public.portal_gateway('ver_encomenda',jsonb_build_object('id',eid2),null,t2,'ip-link');
 if (r->>'id')::int<>eid or r ? 'whatsapp' then raise exception 'Link revelou dados fora da encomenda';end if;
 r:=public.portal_gateway('moradores','{}',null);
 if r->>'codigo'<>'401' then raise exception 'Listagem sem senha permitida';end if;
 blocked:=false;begin perform public.portal_gateway('mudar_morador',jsonb_build_object('id',mid,'confirmacao','A-01'),s);exception when others then blocked:=true;end;
 if not blocked then raise exception 'Mudança com pendências permitida';end if;
 r:=public.portal_gateway('informar_engano','{}',null,t2,'ip-link');
 if r->>'status'<>'DIVERGÊNCIA' then raise exception 'Engano não sinalizado';end if;
 perform public.portal_gateway('resolver_divergencia',jsonb_build_object('id',eid),s);
 perform public.portal_gateway('baixar',jsonb_build_object('id',eid),s);
 if not exists(select 1 from public.encomendas where id=eid and status='ENTREGUE' and recebedor is null)then raise exception 'Baixa simples falhou ou inventou recebedor';end if;
 perform public.portal_gateway('mudar_morador',jsonb_build_object('id',mid,'confirmacao','A-01'),s);
 r:=public.portal_gateway('ver_encomenda','{}',null,t2,'ip-link');
 if r->>'codigo'<>'403' then raise exception 'Morador que mudou manteve link válido';end if;
 -- Nenhuma conta/e-mail é necessário para o cadastro público.
 r:=public.portal_gateway('solicitar_cadastro',jsonb_build_object('bloco','A','apartamento','01','nome','NOVO TESTE','whatsapp','55999991234'),null,null,'ip-cadastro');
 if r->>'ok'<>'true' then raise exception 'Cadastro simples falhou';end if;
 select id into pedido from portal_private.pedidos where bloco='A' and apartamento='01';
 if not exists(select 1 from portal_private.pedidos where id=pedido and whatsapp='5555999991234')then raise exception 'DDD55 incorreto';end if;
 perform public.portal_gateway('aprovar',jsonb_build_object('id',pedido),s);
 select id into mid2 from public.moradores where bloco='A' and apartamento='01' and ativo;
 if mid2=mid or mid2 is null then raise exception 'Cadastro antigo foi reutilizado';end if;
 if not exists(select 1 from public.encomendas where id=eid and morador_id=mid)then raise exception 'Histórico transferido';end if;
 -- Adivinhar ID não confirma retirada sem o token.
 r:=public.portal_gateway('confirmar_retirada',jsonb_build_object('id',eid2),null,repeat('a',64),'ip-invalido');
 if r->>'codigo'<>'403' then raise exception 'Token adivinhado foi aceito';end if;
 if not exists(select 1 from public.encomendas where id=eid2 and status='DISPONÍVEL')then raise exception 'Alterou encomenda alheia';end if;
 perform public.portal_gateway('sair','{}',s);
 r:=public.portal_gateway('moradores','{}',s);
 if r->>'codigo'<>'401' then raise exception 'Sessão encerrada foi aceita';end if;
 if has_function_privilege('anon','public.portal_gateway(text,jsonb,text,text,text)','execute')
 or has_function_privilege('authenticated','public.portal_gateway(text,jsonb,text,text,text)','execute')then raise exception 'Gateway permite chamada sem service_role';end if;
 -- As tentativas inválidas precisam contar mesmo sem senha correta.
 for i in 1..11 loop r:=public.portal_gateway('entrar',jsonb_build_object('senha','errada'),null,null,'ip-limitado');end loop;
 if r->>'codigo'<>'429' then raise exception 'Limite de tentativas ausente';end if;
end $test$;
select 'OK: acesso simples, hash, limite de tentativas, sessão, links, isolamento, baixa sem novas etapas, mudança e histórico' as resultado;
rollback;
