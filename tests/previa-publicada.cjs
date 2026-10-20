const assert=require('node:assert/strict');
const base='https://portalaguamarinha.com.br/nova-versao/';
const endpoint='https://esegzalccqvoypdpencs.supabase.co/functions/v1/portal-simples';
async function post(acao,dados={},token=null,origin='https://portalaguamarinha.com.br'){
 const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json',Origin:origin},body:JSON.stringify({acao,dados,token})});
 const json=await response.json();return {response,json};
}
(async()=>{
 const checks=[['moradores',null,401],['sessao',null,401],['ver_encomenda','b'.repeat(64),403],['confirmar_retirada','c'.repeat(64),403]];
 for(const [action,token,expected] of checks){const {response,json}=await post(action,{},token);assert.equal(response.status,expected,action+': '+JSON.stringify(json));assert.equal(typeof json.erro,'string');assert(!json.sessao&&!json.nome&&!json.whatsapp,'Não deve retornar dados sem autorização');console.log('OK gateway: '+action+' -> '+response.status)}
 const denied=await post('sessao',{},null,'https://example.invalid');assert.equal(denied.response.status,403);console.log('OK: origem externa recusada');
 let cadastro,portaria,admin;
 for(let i=0;i<12;i++){
  [cadastro,portaria,admin]=await Promise.all(['cadastro.html','portaria.html','admin.html'].map(p=>fetch(base+p,{cache:'no-store'}).then(r=>r.text())));
  if(cadastro.includes('cadastro-simples.js')&&portaria.includes('portaria-simples.js')&&admin.includes('acesso-simples-3'))break;
  if(i===11)throw Error('A versão publicada ainda não corresponde ao acesso simples.');
  await new Promise(r=>setTimeout(r,5000));
 }
 assert(!/type=["'](?:email|password)["']/.test(cadastro),'Cadastro não deve exigir conta');
 assert(!/type=["']email["']/.test(portaria),'Portaria não deve exigir e-mail');
 assert(portaria.includes('Senha da portaria')&&portaria.includes('cadastros-moradores'));
 assert(admin.includes('app.js?v=acesso-simples-3'));
 const sources=await Promise.all(['simples.js','portaria-simples.js','cadastro-simples.js','app.js?v=acesso-simples-3'].map(p=>fetch(base+p).then(async r=>{assert.equal(r.status,200,p);return r.text()})));
 assert(sources[0].includes('/functions/v1/portal-simples'));
 assert(sources[1].includes("link.hash='token='"));
 assert(sources[3].includes("new URL('admin.html',location.href).href"));
 console.log('OK: prévia publicada, cadastro sem conta, senha da portaria, scripts e retorno de autenticação para administração.');
 console.log('Nenhum cadastro, encomenda ou mensagem foi criado pelo teste. O teste não substitui o primeiro login com a senha definida pelo administrador.');
})().catch(err=>{console.error(err);process.exitCode=1});
