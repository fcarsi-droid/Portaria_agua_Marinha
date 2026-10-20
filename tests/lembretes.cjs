const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({viewport:{width:390,height:844}});
 await context.route('https://wa.me/**',route=>route.fulfill({contentType:'text/html',body:'<p>Envio simulado</p>'}));
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setContent('<div id="lembrete"></div>');
 await page.addScriptTag({path:path.resolve(process.argv[2]||'lembretes.js')});
 await page.evaluate(()=>{
  window.rows=[
   {id:1,morador_id:10,nome:'MARIA',bloco:'A',apartamento:'01',whatsapp:'(11) 99999-1234',quantidade:2,status:'DISPONÍVEL'},
   {id:2,morador_id:10,nome:'MARIA',bloco:'A',apartamento:'01',whatsapp:'(11) 99999-1234',quantidade:1,status:'DISPONÍVEL'},
   {id:3,morador_id:20,nome:'OUTRO',bloco:'B',apartamento:'02',whatsapp:'5519999995678',quantidade:1,status:'DISPONÍVEL'},
   {id:4,morador_id:10,nome:'MARIA',quantidade:8,status:'ENTREGUE'},
   {id:5,morador_id:10,nome:'MARIA',quantidade:8,status:'DIVERGÊNCIA'},
   {id:6,morador_id:30,nome:'SEM TELEFONE',bloco:'C',apartamento:'03',whatsapp:'123',quantidade:1,status:'DISPONÍVEL'}
  ];
  window.latest=window.rows;window.fetches=0;
  Lembretes.montar(document.getElementById('lembrete'),rows,{atualizar:async()=>{fetches++;return latest}});
 });
 const select=page.getByLabel('Morador com encomendas sem baixa'),button=page.getByRole('button',{name:'Abrir WhatsApp e enviar lembrete'});
 assert(await button.isDisabled());await select.selectOption('10');
 assert((await page.locator('body').innerText()).includes('2 encomendas sem baixa'));
 assert((await page.locator('body').innerText()).includes('(3 volumes)'));
 // Atualiza a contagem antes de preparar o WhatsApp; não reenvia links nem altera encomendas.
 await page.evaluate(()=>window.latest=window.rows.filter(e=>e.id!==2));
 const popupPromise=page.waitForEvent('popup');await button.click();const popup=await popupPromise;
 await popup.waitForURL('https://wa.me/**');
 const url=new URL(popup.url()),msg=url.searchParams.get('text');
 assert.equal(url.pathname,'/5511999991234');assert(msg.includes('*1 encomenda sem baixa*')&&msg.includes('(2 volumes)'));
 assert(!msg.includes('OUTRO'));assert(msg.includes('você, morador'));assert(msg.includes('somente depois de retirar'));
 assert.equal(await page.evaluate(()=>window.fetches),1);await popup.close();
 // Sem pendências atuais, não abre mensagem antiga.
 await page.evaluate(()=>window.latest=[]);await button.click();
 await page.getByText('Este morador não tem mais encomendas sem baixa. Nenhum lembrete foi preparado.').waitFor();
 assert(await button.isDisabled());assert.equal(await page.getByRole('link',{name:'Abrir mensagem no WhatsApp'}).count(),0);
 // Telefone inválido e falha ao consultar pendências não podem produzir envio.
 await page.evaluate(()=>{window.latest=window.rows;Lembretes.montar(document.getElementById('lembrete'),window.rows,{atualizar:async()=>{throw Error('offline')}})});
 await select.selectOption('30');assert(await button.isDisabled());
 await select.selectOption('20');await button.click();
 await page.getByText('Não foi possível atualizar as pendências. Tente novamente; nenhum lembrete foi preparado.').waitFor();
 assert.equal(await page.getByRole('link',{name:'Abrir mensagem no WhatsApp'}).count(),0);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 assert.deepEqual(errors,[]);
 console.log('OK: seleção por morador, contagem e volumes, status, telefone, atualização antes de enviar, isolamento, ausência de pendências, erro de rede e celular. Nenhuma mensagem real enviada.');
 await browser.close();
})().catch(e=>{console.error(e);process.exitCode=1});
