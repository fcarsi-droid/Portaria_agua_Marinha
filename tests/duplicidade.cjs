const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const m={id:1,nome:'MARIA TESTE',bloco:'A',apartamento:'01',whatsapp:'5519999991234'};
const key='agua_marinha_portaria_sessao',token='d'.repeat(64);
let registrations=0,resends=0;
const rows=()=>[{id:7,morador_id:1,nome:m.nome,bloco:m.bloco,apartamento:m.apartamento,whatsapp:m.whatsapp,quantidade:1,status:'DISPONÍVEL',criado_em:'2026-10-15T12:00:00Z',avisos_bloqueados:false,remessas_sem_baixa:1}];
const server=http.createServer((req,res)=>{const p=req.url.split('?')[0];try{const file=path.join(process.cwd(),p==='/'?'index.html':p);res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(file))}catch{res.statusCode=404;res.end()}});

(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const c=await browser.newContext({viewport:{width:390,height:844}});
 await c.addInitScript(({key,token})=>localStorage.setItem(key,token),{key,token});
 await c.route('https://wa.me/**',route=>route.fulfill({contentType:'text/html',body:'Simulado'}));
 const row={id:7,morador_id:1,...m,id:7,quantidade:1,status:'DISPONÍVEL',criado_em:new Date().toISOString()};
 let calls=[];
 await c.route('**/functions/v1/portal-simples',async route=>{
  const b=route.request().postDataJSON();calls.push(b);let data={ok:true},status=200;
  if(b.acao==='moradores')data=[m];
  else if(b.acao==='pendencias')data=[row];
  else if(b.acao==='avisar'){resends++;data={...row,token:'e'.repeat(64)}}
  else if(b.acao==='registrar'){
   registrations++;
   if(b.dados.confirmar_nova_remessa_id===7)data={...row,id:8,token:'f'.repeat(64)};
   else {status=409;data={...row,registro_existente:true,codigo:409,erro:'Já registrado'};}
  }else assert.equal(b.acao,'sessao');
  await route.fulfill({status,contentType:'application/json',body:JSON.stringify(data)});
 });
 const p=await c.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.goto('http://127.0.0.1:'+server.address().port+'/portaria.html');
 await p.locator('.cartao-encomenda').waitFor();
 await p.locator('#bloco').selectOption('A');await p.locator('#apartamento').selectOption('1');
 await p.getByRole('button',{name:'Reenviar aviso deste registro',exact:true}).waitFor();
 await p.getByRole('button',{name:'Registrar e abrir WhatsApp',exact:true}).click();
 await p.getByRole('button',{name:'É outra encomenda',exact:true}).waitFor();
 assert((await p.locator('#aviso-envio').innerText()).includes('Nenhum novo registro foi criado'));
 assert.equal(registrations,1);assert.equal(resends,0);
 await p.getByRole('button',{name:'Reenviar aviso',exact:true}).click();
 await p.getByRole('link',{name:'Abrir WhatsApp e enviar aviso',exact:true}).waitFor();
 assert.equal(resends,1);assert.equal(registrations,1);
 await p.getByRole('button',{name:'Registrar e abrir WhatsApp',exact:true}).click();
 await p.getByRole('button',{name:'É outra encomenda',exact:true}).click();
 await p.waitForFunction(()=>document.getElementById('aviso-envio').textContent.includes('Registro #8 salvo'));
 assert.equal(registrations,3);assert.equal(calls.filter(x=>x.acao==='registrar'&&x.dados.confirmar_nova_remessa_id===7).length,1);
 assert(!calls.some(x=>['baixar','confirmar_retirada'].includes(x.acao)));
 assert.deepEqual(errors,[]);
 console.log('OK: último registro visível, HTTP409 mostra registro existente, reenvio sem registrar, outra encomenda exige confirmação. Nenhuma mensagem real.');
 await browser.close();server.close();
})().catch(e=>{console.error(e);server.close();process.exitCode=1});
