'use strict';
window.Lembretes = (() => {
 const telefone=value=>{let n=String(value??'').replace(/\D/g,'');if(n.length===10||n.length===11)n='55'+n;return /^55[1-9][0-9][0-9]{8,9}$/.test(n)?n:null};
 function agrupar(rows){
  const map=new Map(),vistos=new Set();
  for(const e of rows||[]){
   if(e.status!=='DISPONÍVEL'||e.morador_ativo===false||e.morador_id==null||vistos.has(String(e.id)))continue;
   vistos.add(String(e.id));const key=String(e.morador_id),m=e.moradores||e;
   if(!map.has(key))map.set(key,{id:key,nome:m.nome||'Morador',bloco:m.bloco||'?',apartamento:m.apartamento||'?',whatsapp:m.whatsapp,registros:0,volumes:0});
   const g=map.get(key);g.registros++;g.volumes+=Number(e.quantidade)||0;
  }
  return [...map.values()].sort((a,b)=>(a.bloco+' '+a.apartamento+' '+a.nome).localeCompare(b.bloco+' '+b.apartamento+' '+b.nome,'pt-BR',{numeric:true}));
 }
 function mensagem(m){
  const encomendas=m.registros===1?'1 encomenda':m.registros+' encomendas';
  const volumes=m.volumes===1?'1 volume':m.volumes+' volumes';
  return '📦 *CONDOMÍNIO ÁGUA MARINHA*\n\nOlá, '+m.nome+'!\nUnidade '+m.bloco+'-'+m.apartamento+'.\n\nVocê tem *'+encomendas+' sem baixa* no sistema ('+volumes+').\n\nA confirmação de retirada deve ser feita por você, morador, pelo link enviado no aviso de cada encomenda. Essa confirmação é o seu protocolo de recebimento.\n\nSe já retirou, abra os avisos no WhatsApp e confirme o recebimento. Se ainda não retirou, confirme somente depois de retirar do armário.\n\nCaso não encontre algum aviso ou perceba uma divergência, entre em contato com a portaria.';
 }
 function montar(host,rows,opcoes={}){
  if(!host)return;
  const anterior=host.querySelector('select')?.value||'',base=host.id||'lembrete-morador';let grupos=agrupar(rows),busy=false;
  host.replaceChildren();
  const label=document.createElement('label');label.htmlFor=base+'-select';label.textContent='Morador com encomendas sem baixa';
  const select=document.createElement('select');select.id=label.htmlFor;select.style.cssText='width:100%;max-width:100%;padding:12px;margin:6px 0 12px;border:1px solid #cbd5e1;border-radius:10px;font:inherit;background:white;color:#1e293b';
  const resumo=document.createElement('p');resumo.setAttribute('role','status');resumo.style.marginBottom='10px';
  const preview=document.createElement('p');preview.hidden=true;preview.style.cssText='white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px;line-height:1.6;background:#f1f5f9;border-radius:10px;padding:12px;margin-bottom:12px;color:#1e293b';
  const button=document.createElement('button');button.type='button';button.className='btn-xls primary';button.textContent='Abrir WhatsApp e enviar lembrete';button.style.minHeight='44px';
  const fallback=document.createElement('a');fallback.hidden=true;fallback.style.display='none';fallback.target='_blank';fallback.rel='noopener noreferrer';fallback.className='btn-xls button';fallback.textContent='Abrir mensagem no WhatsApp';fallback.style.marginTop='10px';
  const nota=document.createElement('p');nota.className='meta';nota.textContent='Conclua o envio no WhatsApp.';nota.style.cssText='font-size:12px;margin-top:8px;color:#64748b';
  host.append(label,select,resumo,preview,button,fallback,nota);
  const escolhido=()=>grupos.find(m=>m.id===select.value);
  function preencher(keep){
   select.replaceChildren(new Option(grupos.length?'Selecione o morador':'Nenhum morador com encomendas sem baixa',''));
   for(const m of grupos)select.add(new Option(m.bloco+'-'+m.apartamento+' · '+m.nome+' · '+m.registros+' encomenda(s)',m.id));
   if(grupos.some(m=>m.id===keep))select.value=keep;
   atualizar();
  }
  function atualizar(){
   const m=escolhido();fallback.hidden=true;fallback.style.display='none';fallback.removeAttribute('href');button.disabled=busy||!m||!telefone(m.whatsapp);
   preview.hidden=!m;preview.textContent=m?mensagem(m):'';
   resumo.textContent=!m?(grupos.length?'Selecione um morador para conferir a mensagem.':'Nenhuma encomenda aguardando confirmação de retirada.'):(m.registros+' encomenda(s) sem baixa · '+m.volumes+' volume(s)'+(!telefone(m.whatsapp)?'. WhatsApp inválido ou não cadastrado.':''));
  }
  select.addEventListener('change',atualizar);
  button.addEventListener('click',async()=>{
   if(busy)return;let m=escolhido();if(!m||!telefone(m.whatsapp))return;
   const id=m.id;busy=true;button.disabled=true;select.disabled=true;fallback.hidden=true;fallback.style.display='none';
   const janela=window.open('about:blank','_blank');if(janela)janela.opener=null;
   try{
    if(opcoes.atualizar){const latest=await opcoes.atualizar();grupos=agrupar(latest);preencher(id);m=escolhido()}
    if(!m){janela?.close();resumo.textContent='Este morador não tem mais encomendas sem baixa. Nenhum lembrete foi preparado.';return}
    const tel=telefone(m.whatsapp);if(!tel){janela?.close();resumo.textContent='WhatsApp inválido ou não cadastrado. Confira o cadastro.';return}
    const url='https://wa.me/'+tel+'?text='+encodeURIComponent(mensagem(m));fallback.href=url;fallback.hidden=false;fallback.style.display='inline-flex';
    if(janela)janela.location.replace(url);
    resumo.textContent='Mensagem preparada com '+m.registros+' encomenda(s) sem baixa. Conclua o envio no WhatsApp.';
   }catch{janela?.close();resumo.textContent='Não foi possível atualizar as pendências. Tente novamente; nenhum lembrete foi preparado.'}
   finally{busy=false;select.disabled=false;button.disabled=!escolhido()||!telefone(escolhido()?.whatsapp)}
  });
  preencher(anterior);
 }
 return {agrupar,mensagem,montar};
})();
