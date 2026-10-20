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
 if p_acao in ('solicitacoes','aprovar','rejeitar') then
   return jsonb_build_object('erro','Cadastros são gerenciados somente pela administração.','codigo',403);
 end if;
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
   t:=encode(extensions.gen_random_bytes(32),'hex');
   update portal_private.links_encomendas set revogado=true where encomenda_id=enc.id and not revogado;
   insert into portal_private.links_encomendas(token_hash,encomenda_id,expira_em) values(encode(extensions.digest(t,'sha256'),'hex'),enc.id,now()+interval '30 days');
   return to_jsonb(enc)||jsonb_build_object('token',t);
 end if;
 return portal_private.operar_portaria(sess.id,p_acao,p_dados);
end $function$
