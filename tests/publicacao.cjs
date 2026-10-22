const assert=require('node:assert/strict');
const base='https://portalaguamarinha.com.br/';
const endpoint='https://esegzalccqvoypdpencs.supabase.co/functions/v1/portal-simples';
async function get(path){const r=await fetch(base+path+'?publicacao='+Date.now(),{cache:'no-store'});assert.equal(r.status,200,path);return r.text()}
(async()=>{
 let pages;
 for(let i=0;i<30;i++){
  pages=await Promise.all(['index.html','portaria.html','cadastro.html','admin.html'].map(get));
  if(pages.every(s=>s.includes('20261020-publicada')))break;
  if(i===29)throw Error('A publicação no endereço principal não foi concluída.');
  await new Promise(r=>setTimeout(r,5000));
 }
 const [index,portaria,cadastro,admin]=pages;
 assert(index.includes('admin.html'));
 assert(portaria.includes('portaria-simples.js')&&portaria.includes('cadastros-moradores'));
 assert(!portaria.includes('cadastros-solicitacoes'));
 assert(portaria.indexOf('id="cadastros-moradores"')<portaria.indexOf('<!-- Registro -->'));
 assert(!/type=["']email["']/.test(portaria));
 assert(!/type=["'](?:email|password)["']/.test(cadastro));
 assert(!cadastro.includes('Após conferência da portaria'));
 assert(admin.includes('vendor/supabase-2.118.0.js'));
 const [portal,porter,resident,management]=await Promise.all(['simples.js','portaria-simples.js','cadastro-simples.js','app.js'].map(get));
 for(const s of [portal,porter,resident,management])new Function(s);
 assert(!porter.includes('carregarSolicitacoes'));
 assert(porter.includes('avisos_bloqueados')&&management.includes('avisos_bloqueados'));assert(portal.includes('localStorage.setItem(sessionKey,value)'));
 assert(resident.includes('aprovação da administração'));
 assert(management.includes("new URL('admin.html',location.href).href"));
 await get('app.css');await get('vendor/supabase-2.118.0.js');
 for(const [acao,token,status] of [['moradores',null,401],['sessao',null,401],['ver_encomenda','a'.repeat(64),403]]){
  const r=await fetch(endpoint,{method:'POST',headers:{Origin:'https://portalaguamarinha.com.br','Content-Type':'application/json'},body:JSON.stringify({acao,dados:{},token})});const j=await r.json();assert.equal(r.status,status);assert(!j.nome&&!j.whatsapp&&!j.sessao);
 }
 console.log('OK: endereço principal, todos os arquivos, mudança no alto, cadastro sem conta, aprovação exclusiva da administração, regra de suspensão presente, sessão persistente e gateway protegido.');
 console.log('Nenhuma mensagem, conta ou encomenda foi criada.');
})().catch(e=>{console.error(e);process.exitCode=1});
