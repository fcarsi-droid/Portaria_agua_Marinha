const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const nome='MARIA APARECIDA DOS SANTOS DE OLIVEIRA E SILVA';
const morador={id:1,nome,bloco:'A',apartamento:'01',whatsapp:'5519999991234'};
const rows=[{id:7,morador_id:1,...morador,id:7,quantidade:3,status:'DIVERGÊNCIA',criado_em:'2026-10-19T11:30:00Z'},{id:8,morador_id:1,...morador,id:8,quantidade:1,status:'DISPONÍVEL',criado_em:'2026-10-20T15:45:00Z'}];
const server=http.createServer((req,res)=>{const p=req.url.split('?')[0];try{const file=path.join(process.cwd(),p==='/'?'index.html':p);res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(file))}catch{res.statusCode=404;res.end()}});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});const context=await browser.newContext({viewport:{width:390,height:844}});
 await context.addInitScript(()=>sessionStorage.setItem('agua_marinha_portaria_sessao','a'.repeat(64)));
 await context.route('**/functions/v1/portal-simples',async route=>{const b=route.request().postDataJSON();let result;if(b.acao==='sessao')result={ok:true};else if(b.acao==='moradores')result=[morador];else if(b.acao==='pendencias')result=rows;else if(b.acao==='devolver'){assert.equal(Number(b.dados.id),7);rows.splice(rows.findIndex(e=>e.id===7),1);result={ok:true}}else throw Error('Ação inesperada: '+b.acao);await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(result)})});
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(url+'/portaria.html');await page.locator('.cartao-encomenda').first().waitFor();
 assert.equal(await page.locator('.cartao-encomenda').count(),2);assert.equal(await page.locator('[data-baixa]').first().getAttribute('data-baixa'),'8');
 for(const width of [320,390,430,1024]){
  await page.setViewportSize({width,height:900});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Rolagem horizontal em '+width);
  for(const id of ['atalho-mudanca','atalho-lembrete']){
   const box=await page.locator('#'+id).boundingBox();assert(box.height>=44&&box.y<440,'Atalho escondido em '+width);
  }
  const name=page.locator('.encomenda-nome').first();assert.equal(await name.innerText(),nome);
  assert(await name.evaluate(e=>{const s=getComputedStyle(e);return s.whiteSpace==='normal'&&s.textOverflow!=='ellipsis'&&e.scrollHeight<=e.clientHeight&&parseFloat(s.fontSize)>=16}),'Nome cortado em '+width);
  for(const b of await page.locator('.cartao-encomenda').first().locator('button').all())assert((await b.boundingBox()).height>=44);
  assert((await page.locator('.cartao-encomenda').first().innerText()).includes('Bloco A · Apto 01'));
  assert((await page.locator('.cartao-encomenda').first().innerText()).includes('1 volume(s)'));
  assert((await page.locator('.encomenda-data').first().innerText()).includes('20/10/2026'));
 }
 await page.setViewportSize({width:390,height:844});await page.locator('#atalho-mudanca').click();await page.locator('[data-mudanca]').waitFor();
 assert.equal(await page.locator('#atalho-mudanca').getAttribute('aria-expanded'),'true');
 await page.locator('#atalho-lembrete').click();await page.getByLabel('Morador com encomendas sem baixa').selectOption('1');
 assert(await page.locator('#painel-lembrete').evaluate(e=>e.open));assert(!(await page.locator('#cadastros-moradores').evaluate(e=>e.open)));
 assert((await page.locator('#lembrete-morador').innerText()).includes('2 encomendas sem baixa'));
 await page.locator('#atalho-lembrete').click();assert(!(await page.locator('#painel-lembrete').evaluate(e=>e.open)));
 await page.locator('[data-baixa]').first().click();await page.locator('#modal-overlay.aberto').waitFor();await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 await page.locator('[data-devolver="7"]').click();await page.getByRole('button',{name:'Confirmar devolução à portaria',exact:true}).waitFor();
 assert(!(await page.locator('#modal-overlay').innerText()).includes('transportador'));
 await page.getByRole('button',{name:'Confirmar devolução à portaria',exact:true}).click();
 await page.waitForFunction(()=>document.querySelectorAll('.cartao-encomenda').length===1);
 assert.equal(await page.locator('[data-devolver]').count(),0);
 assert.deepEqual(errors,[]);
 console.log('OK: atalhos visíveis, abertura e foco, lembrete, nome completo, unidade, volumes, data, botões de toque, ordem e ausência de rolagem horizontal em 320/390/430/1024px. Sem gravações ou mensagens.');
 await browser.close();server.close();
})().catch(e=>{console.error(e);server.close();process.exit(1)});
