const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const m={id:1,nome:'MARIA TESTE',bloco:'A',apartamento:'01',whatsapp:'5519999991234'};
const key='agua_marinha_portaria_sessao',token='d'.repeat(64);
let offline=false,blocked=false,logins=0,registrations=0;
const rows=()=>[{id:7,morador_id:1,nome:m.nome,bloco:m.bloco,apartamento:m.apartamento,whatsapp:m.whatsapp,quantidade:1,status:'DISPONÍVEL',criado_em:'2026-10-15T12:00:00Z',avisos_bloqueados:blocked,remessas_sem_baixa:blocked?11:1}];
const server=http.createServer((req,res)=>{const p=req.url.split('?')[0];try{const file=path.join(process.cwd(),p==='/'?'index.html':p);res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(file))}catch{res.statusCode=404;res.end()}});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 async function contexto(storageState){const c=await browser.newContext({viewport:{width:390,height:844},...(storageState?{storageState}:{})});
  await c.route('https://wa.me/**',route=>route.fulfill({contentType:'text/html',body:'Simulado'}));
  await c.route('**/functions/v1/portal-simples',async route=>{
   const b=route.request().postDataJSON();let data={ok:true},status=200;
   if(b.acao==='entrar'){logins++;data={sessao:token}}
   else if(b.acao==='sessao'&&offline){status=503;data={erro:'Sem conexão temporária'}}
   else if(b.acao==='moradores')data=[m];
   else if(b.acao==='pendencias')data=rows();
   else if(b.acao==='registrar'||b.acao==='avisar'){
    if(b.acao==='registrar')registrations++;
    data={...rows()[0],...(blocked?{codigo:409,erro:'Remessa registrada. Avisos suspensos por pendências sem baixa.',mensagem_suspensao:'Você tem 11 remessas sem baixa e o primeiro aviso pendente completou 4 dias.'}:{token:'e'.repeat(64)})};if(blocked)status=409;
   }
   else if(!['sessao','sair'].includes(b.acao))throw Error('Ação inesperada: '+b.acao);
   if(!['entrar'].includes(b.acao))assert.equal(route.request().headers().authorization,'Bearer '+token);
   await route.fulfill({status,contentType:'application/json',body:JSON.stringify(data)});
  });return c;
 }
 let c=await contexto(),p=await c.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.goto(url+'/portaria.html');await p.getByRole('textbox',{name:'Senha da portaria'}).fill('teste-seguro-123');await p.getByRole('button',{name:'Entrar',exact:true}).click();await p.locator('.cartao-encomenda').waitFor();
 assert.equal(await p.evaluate(k=>localStorage.getItem(k),key),token);assert.equal(await p.evaluate(k=>sessionStorage.getItem(k),key),null);
 let p2=await c.newPage();await p2.goto(url+'/portaria.html');await p2.locator('.cartao-encomenda').waitFor();assert.equal(logins,1);
 const state=await c.storageState();await c.close();c=await contexto(state);p=await c.newPage();p.on('pageerror',e=>errors.push(e.message));await p.goto(url+'/portaria.html');await p.locator('.cartao-encomenda').waitFor();assert.equal(logins,1);
 offline=true;await p.reload();await p.getByRole('button',{name:'Tentar novamente',exact:true}).waitFor();assert.equal(await p.evaluate(k=>localStorage.getItem(k),key),token);assert(!(await p.locator('#senha-input').isVisible()));
 offline=false;await p.getByRole('button',{name:'Tentar novamente',exact:true}).click();await p.locator('.cartao-encomenda').waitFor();assert.equal(logins,1);
 blocked=true;await p.getByRole('button',{name:'Atualizar lista',exact:true}).click();await p.getByText('Avisos suspensos · 11 remessas sem baixa',{exact:true}).waitFor();
 await p.locator('#bloco').selectOption('A');await p.locator('#apartamento').selectOption('1');await p.getByRole('button',{name:'Registrar e abrir WhatsApp'}).click();
 await p.getByRole('link',{name:'Informar suspensão no WhatsApp'}).waitFor();assert.equal(registrations,1);
 const href=await p.getByRole('link',{name:'Informar suspensão no WhatsApp'}).getAttribute('href');assert(!href.includes('token%3D'));assert(decodeURIComponent(href).includes('11 remessas'));
 assert.equal(await p.evaluate(k=>localStorage.getItem(k),key),token);
 await p.getByRole('button',{name:'Sair',exact:true}).click();await p.getByRole('button',{name:'Entrar',exact:true}).waitFor();assert.equal(await p.evaluate(k=>localStorage.getItem(k),key),null);
 assert.deepEqual(errors,[]);
 console.log('OK: sessão entre abas e reabertura, sem login repetido; erro temporário preserva acesso; logout remove acesso; HTTP 409 registra sem aviso de chegada e exibe suspensão. Sem mensagens reais.');
 await browser.close();server.close();
})().catch(e=>{console.error(e);server.close();process.exitCode=1});
