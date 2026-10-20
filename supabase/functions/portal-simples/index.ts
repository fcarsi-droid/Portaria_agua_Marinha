import { createClient } from "npm:@supabase/supabase-js@2.118.0";
const allowed=new Set(["https://portalaguamarinha.com.br","https://www.portalaguamarinha.com.br"]);
const actions=new Set(["entrar","sair","sessao","solicitar_cadastro","ver_encomenda","confirmar_retirada","informar_engano","moradores","pendencias","registrar","avisar","baixar","devolver","resolver_divergencia","mudar_morador","solicitacoes","aprovar","rejeitar","historico","ex_moradores"]);
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get("origin")||"";
 const headers={"Content-Type":"application/json","Cache-Control":"no-store","Vary":"Origin","Access-Control-Allow-Origin":allowed.has(origin)?origin:"https://portalaguamarinha.com.br","Access-Control-Allow-Headers":"authorization,content-type,apikey,x-client-info","Access-Control-Allow-Methods":"POST,OPTIONS"};
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(origin&&!allowed.has(origin))return reply({erro:"Origem não autorizada."},403);
 if(req.method==="OPTIONS")return new Response("ok",{headers});
 if(req.method!=="POST")return reply({erro:"Método não permitido."},405);
 try{
  const raw=await req.text();if(new TextEncoder().encode(raw).length>6000)return reply({erro:"Solicitação muito grande."},413);
  const body=JSON.parse(raw);if(!actions.has(body.acao)||!body.dados||Array.isArray(body.dados)||typeof body.dados!=="object")return reply({erro:"Solicitação inválida."},400);
  const secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const url=Deno.env.get("SUPABASE_URL")!;
  const ip=(req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim();
  const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(secret+":"+ip));
  const origem=Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,"0")).join("");
  const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const bearer=req.headers.get("authorization")||"";
  const session=bearer.startsWith("Bearer ")?bearer.slice(7):null;
  if(session&&session.length>128)return reply({erro:"Sessão inválida."},401);
  if(body.token&&typeof body.token!=="string")return reply({erro:"Link inválido."},400);
  const {data,error}=await db.rpc("portal_gateway",{p_acao:body.acao,p_dados:body.dados,p_sessao:session,p_token:body.token||null,p_origem:origem});
  if(error){const message=error.code==="P0001"?error.message:"Não foi possível concluir. Confira os dados e tente novamente.";return reply({erro:message},400)}
  return reply(data,data?.erro?(data.codigo||400):200);
 }catch{return reply({erro:"Não foi possível processar. Confira os dados e tente novamente."},400)}
});
