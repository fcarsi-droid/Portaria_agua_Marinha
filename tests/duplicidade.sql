BEGIN;
DO $test$
declare mid int; sid uuid; t text:=encode(extensions.gen_random_bytes(32),'hex'); op uuid:=gen_random_uuid(); op2 uuid:=gen_random_uuid(); r jsonb; original jsonb; newid int; d jsonb;
begin
 insert into portal_private.sessoes_portaria(token_hash,expira_em) values(encode(extensions.digest(t,'sha256'),'hex'),now()+interval '1 day') returning id into sid;
 insert into public.moradores(bloco,apartamento,nome,whatsapp,ativo) values('TESTE-'||gen_random_uuid(),'99','Teste de repetição','5519999991234',true) returning id into mid;
 d:=jsonb_build_object('morador_id',mid,'quantidade',1,'operacao_id',op);
 original:=portal_private.gateway('registrar',d,t);
 assert original->>'token' is not null,'primeiro registro deve gerar link';
 r:=portal_private.gateway('registrar',d,t);
 assert r->>'registro_existente'='true' and r->>'id'=original->>'id' and not(r?'token'),'repetição da operação não deve gerar novo link';
 d:=d||jsonb_build_object('operacao_id',op2);
 r:=portal_private.gateway('registrar',d,t);
 assert r->>'registro_existente'='true' and r->>'id'=original->>'id','mesma unidade e quantidade exige confirmação';
 assert (select count(*) from public.encomendas where morador_id=mid)=1,'não pode duplicar';
 r:=portal_private.gateway('ver_encomenda','{}',null,original->>'token','teste-duplicidade');
 assert r->>'id'=original->>'id','link inicial deve continuar válido';
 d:=d||jsonb_build_object('confirmar_nova_remessa_id',(original->>'id')::int);
 r:=portal_private.gateway('registrar',d,t);newid:=(r->>'id')::int;
 assert newid<>(original->>'id')::int and r->>'token' is not null,'outra encomenda confirmada deve registrar';
 r:=portal_private.gateway('registrar',d,t);
 assert r->>'registro_existente'='true' and (r->>'id')::int=newid,'repetir confirmação não deve criar terceiro';
 assert (select count(*) from public.encomendas where morador_id=mid)=2,'somente duas remessas';
 r:=portal_private.gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',2,'operacao_id',gen_random_uuid()),t);
 assert r->>'token' is not null,'quantidade diferente deve permitir';
 update public.encomendas set criado_em=now()-interval '6 minutes' where morador_id=mid;
 r:=portal_private.gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',1,'operacao_id',gen_random_uuid()),t);
 assert r->>'token' is not null,'fora da janela permite';
 update public.encomendas set status='DIVERGÊNCIA' where id=(r->>'id')::int;
 r:=portal_private.gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',1,'operacao_id',gen_random_uuid()),t);
 assert r->>'registro_existente'='true' and r->>'status'='DIVERGÊNCIA' and not(r?'token'),'divergência recente também protegida';
 -- Preserve the authorized 11 shipments / oldest 96h rule.
 insert into public.encomendas(morador_id,quantidade,status,criado_em) select mid,1,'DISPONÍVEL',now()-interval '5 days' from generate_series(1,8);
 r:=portal_private.gateway('registrar',jsonb_build_object('morador_id',mid,'quantidade',3,'operacao_id',gen_random_uuid()),t);
 assert r->>'avisos_bloqueados'='true' and not(r?'token'),'bloqueio autorizado deve continuar';
end $test$;
SELECT 'OK: repetição, reenvio preservado, confirmação explícita, quantidade, prazo, divergência e bloqueio' as resultado;
ROLLBACK;