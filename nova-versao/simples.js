'use strict';
window.Portal = (() => {
 const endpoint='https://esegzalccqvoypdpencs.supabase.co/functions/v1/portal-simples';
 const sessionKey='agua_marinha_portaria_sessao';
 const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const telefone=value=>{let n=String(value??'').replace(/\D/g,'');if(n.length===10||n.length===11)n='55'+n;return /^55[1-9][0-9][0-9]{8,9}$/.test(n)?n:null};
 let sessao=sessionStorage.getItem(sessionKey);
 async function call(acao,dados={},token=null){
  const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json',...(sessao?{Authorization:'Bearer '+sessao}:{})},body:JSON.stringify({acao,dados,token}),cache:'no-store'});
  let result;try{result=await response.json()}catch{throw Error('Não foi possível conectar ao portal. Tente novamente.')}
  if(!response.ok||result.erro){const error=Error(result.erro||'Não foi possível concluir. Tente novamente.');error.status=response.status;if(response.status===401&&acao!=='entrar')clear();throw error}
  return result;
 }
 function save(value){sessao=value;sessionStorage.setItem(sessionKey,value)}
 function clear(){sessao=null;sessionStorage.removeItem(sessionKey);localStorage.removeItem('portaria_logado')}
 function token(){return new URLSearchParams(location.hash.slice(1)).get('token')}
 function dias(value){const d=new Date(value),n=new Date();return Math.max(0,Math.round((Date.UTC(n.getFullYear(),n.getMonth(),n.getDate())-Date.UTC(d.getFullYear(),d.getMonth(),d.getDate()))/86400000))}
 return {call,save,clear,hasSession:()=>!!sessao,escape,telefone,token,dias};
})();
document.addEventListener('DOMContentLoaded',()=>{
 document.querySelectorAll('.field').forEach(field=>{const l=field.querySelector('label'),e=field.querySelector('input,select');if(l&&e?.id)l.htmlFor=e.id});
 document.querySelectorAll('.toast,[id$="-erro"],#status-box').forEach(e=>e.setAttribute('role','status'));
 document.querySelectorAll('input[type="password"]').forEach(e=>{e.setAttribute('aria-label',e.placeholder);e.autocomplete='current-password'});
 const overlay=document.getElementById('modal-overlay');
 if(overlay){const modal=overlay.querySelector('.modal');modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-label',modal.querySelector('h3')?.textContent||'Confirmar');let previous;
 new MutationObserver(()=>{if(overlay.classList.contains('aberto')){previous=document.activeElement;modal.querySelector('button')?.focus()}else previous?.focus()}).observe(overlay,{attributes:true,attributeFilter:['class']});
 document.addEventListener('keydown',e=>{if(!overlay.classList.contains('aberto'))return;if(e.key==='Escape')fecharModal();if(e.key==='Tab'){const bs=[...modal.querySelectorAll('button:not(:disabled),input:not(:disabled)')];if(e.shiftKey&&document.activeElement===bs[0]){e.preventDefault();bs.at(-1)?.focus()}else if(!e.shiftKey&&document.activeElement===bs.at(-1)){e.preventDefault();bs[0]?.focus()}}});
 }
});
