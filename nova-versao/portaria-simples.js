
const encomendaId=new URLSearchParams(location.search).get('id');
const encomendaToken=Portal.token();
let itemParaBaixa=null,modoModal='baixar',registrando=false,baixando=false,operacaoId=null,ultimaOperacao='';
window.moradoresGlobal=[];window.pendenciasGlobal=[];
function toast(msg,tipo=''){const el=document.getElementById('toast');el.textContent=msg;el.className='toast show '+tipo;setTimeout(()=>el.className='toast',5000)}
function atualizarHora(){document.getElementById('hora-atual').textContent=new Date().toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})}
function mostrarLogin(msg=''){document.getElementById('visao-porteiro').style.display='none';document.getElementById('login-screen').classList.remove('hidden');if(msg){const e=document.getElementById('login-erro');e.textContent=msg;e.style.display='block'}}
async function inicializar(){
 if(encomendaId||encomendaToken){document.getElementById('visao-morador').classList.remove('hidden');await exibirVisaoMorador();return}
 if(Portal.hasSession()){try{await Portal.call('sessao');await exibirVisaoPorteiro();return}catch{Portal.clear()}}
 mostrarLogin();
}
async function verificarSenha(){const btn=document.querySelector('.btn-login');if(btn.disabled)return;btn.disabled=true;try{const data=await Portal.call('entrar',{senha:document.getElementById('senha-input').value});Portal.save(data.sessao);document.getElementById('senha-input').value='';await exibirVisaoPorteiro()}catch(e){mostrarLogin(e.message)}finally{btn.disabled=false}}
document.getElementById('senha-input').addEventListener('keydown',e=>{if(e.key==='Enter')verificarSenha()});
async function logout(){try{await Portal.call('sair')}catch{}Portal.clear();mostrarLogin();window.moradoresGlobal=[];window.pendenciasGlobal=[]}
async function exibirVisaoPorteiro(){const data=await Portal.call('moradores');window.moradoresGlobal=data;const sel=document.getElementById('bloco');sel.replaceChildren(new Option('–',''));[...new Set(data.map(m=>m.bloco))].sort().forEach(b=>sel.add(new Option('Bloco '+b,b)));document.getElementById('login-screen').classList.add('hidden');document.getElementById('visao-porteiro').style.display='block';atualizarHora();await carregarPendencias()}
function filtrarApartamentos(){const bloco=document.getElementById('bloco').value,sel=document.getElementById('apartamento');sel.replaceChildren(new Option('Selecione',''));document.getElementById('morador-sel').classList.remove('ativo');window.moradoresGlobal.filter(m=>String(m.bloco)===bloco).forEach(m=>sel.add(new Option(m.apartamento+' – '+m.nome,m.id)))}
function mostrarMorador(){const m=window.moradoresGlobal.find(m=>String(m.id)===document.getElementById('apartamento').value),el=document.getElementById('morador-sel');if(!m){el.classList.remove('ativo');return}document.getElementById('morador-av').textContent=m.nome.trim().split(' ').slice(0,2).map(n=>n[0]).join('');document.getElementById('morador-sel-nome').textContent=m.nome;document.getElementById('morador-sel-sub').textContent='Bloco '+m.bloco+' · Apto '+m.apartamento;el.classList.add('ativo')}
function ajustarVol(d){const el=document.getElementById('qtd');el.value=Math.max(1,Math.min(99,(Number(el.value)||1)+d))}
async function registrar(){if(registrando)return;const id=document.getElementById('apartamento').value,qtd=Number(document.getElementById('qtd').value);if(!id)return toast('Selecione o apartamento');if(!Number.isInteger(qtd)||qtd<1||qtd>99)return toast('Informe de 1 a 99 volumes');const morador=window.moradoresGlobal.find(m=>String(m.id)===id);if(!morador)return;
 const fingerprint=id+':'+qtd;if(fingerprint!==ultimaOperacao){operacaoId=crypto.randomUUID();ultimaOperacao=fingerprint}
 registrando=true;const btn=document.querySelector('.btn-registrar');btn.disabled=true;
 // Abre na ação do clique para evitar bloqueio de popup após a gravação assíncrona.
 const janela=Portal.telefone(morador.whatsapp)?window.open('about:blank','_blank'):null;if(janela)janela.opener=null;
 try{const item=await Portal.call('registrar',{morador_id:id,quantidade:qtd,operacao_id:operacaoId});ultimaOperacao='';operacaoId=null;document.getElementById('bloco').value='';document.getElementById('apartamento').replaceChildren(new Option('Selecione o bloco',''));document.getElementById('qtd').value=1;document.getElementById('morador-sel').classList.remove('ativo');abrirAviso(item,morador,janela);toast('Encomenda salva. Conclua o envio no WhatsApp.','green');await carregarPendencias()}catch(e){janela?.close();toast(e.message)}finally{registrando=false;btn.disabled=false}
}
function abrirAviso(item,m,janela=null){const tel=Portal.telefone(m.whatsapp);const box=document.getElementById('aviso-envio');box.hidden=false;box.replaceChildren();if(!tel){box.textContent='Registro salvo. Morador sem WhatsApp válido; avise por outro meio.';return}
 const link=new URL('portaria.html',location.href);link.searchParams.set('id',item.id);link.hash='token='+item.token;
 const msg='📦 *CONDOMÍNIO ÁGUA MARINHA*\n\nOlá *'+m.nome+'*, chegou *'+item.quantidade+' volume(s)* para sua unidade.\nRetire na portaria e confirme somente após receber:\n'+link.href;
 const url='https://wa.me/'+tel+'?text='+encodeURIComponent(msg);const texto=document.createElement('p');texto.textContent='Encomenda registrada. Se o WhatsApp não abriu, use o botão abaixo.';const a=document.createElement('a');a.href=url;a.target='_blank';a.rel='noopener noreferrer';a.className='btn-xls';a.textContent='Abrir WhatsApp e enviar aviso';box.append(texto,a);if(janela)janela.location.replace(url)
}
async function avisar(id){const enc=window.pendenciasGlobal.find(e=>String(e.id)===String(id));if(!enc)return;const janela=Portal.telefone(enc.moradores.whatsapp)?window.open('about:blank','_blank'):null;if(janela)janela.opener=null;try{const item=await Portal.call('avisar',{id});abrirAviso(item,enc.moradores,janela)}catch(e){janela?.close();toast(e.message)}}
async function carregarPendencias(){try{const data=await Portal.call('pendencias');window.pendenciasGlobal=data.map(e=>({...e,moradores:{nome:e.nome||'Cadastro indisponível',bloco:e.bloco||'?',apartamento:e.apartamento||'?',whatsapp:e.whatsapp}}));document.getElementById('badge-total').textContent=data.length;filtrarPendencias()}catch(e){document.getElementById('resumo-pendencias').textContent='Não foi possível atualizar. Os dados podem estar desatualizados.';if(e.status===401)mostrarLogin(e.message);else toast(e.message)}}
function filtrarPendencias(){const norm=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();const term=norm(document.getElementById('busca-pendencias').value).trim();const list=window.pendenciasGlobal.filter(e=>term.split(/\s+/).every(t=>norm(e.moradores.nome+' '+e.moradores.bloco+'-'+e.moradores.apartamento).includes(t)));document.getElementById('resumo-pendencias').textContent=list.length+' registro(s) · '+list.reduce((n,e)=>n+Number(e.quantidade),0)+' volume(s)';renderLista(list)}
function abrirModalById(id){const enc=window.pendenciasGlobal.find(e=>String(e.id)===String(id));if(!enc)return;modoModal='baixar';itemParaBaixa=enc;prepararModal('Confirmar retirada',enc.moradores.bloco+'-'+enc.moradores.apartamento,enc.moradores.nome+' · '+enc.quantidade+' volume(s)','', 'Confirmar Retirada')}
function devolver(id){const enc=window.pendenciasGlobal.find(e=>String(e.id)===String(id));if(!enc)return;modoModal='devolver';itemParaBaixa=enc;prepararModal('Registrar devolução',enc.moradores.bloco+'-'+enc.moradores.apartamento,'Use somente após devolver os volumes ao remetente/transportador.','<label for="motivo-devolucao">Motivo da devolução</label><input id="motivo-devolucao" maxlength="500" placeholder="Informe o motivo">','Confirmar devolução')}
function prepararModal(titulo,apto,nome,extra,label){document.querySelector('#modal-overlay h3').textContent=titulo;document.querySelector('#modal-overlay .modal > p').textContent=modoModal==='mudar_morador'?'O cadastro será desativado e o apartamento liberado. O histórico será preservado.':'Confirme a operação após conferir os volumes.';document.getElementById('modal-apto').textContent=apto;document.getElementById('modal-nome').textContent=nome;document.getElementById('dados-operacao').innerHTML=extra;document.querySelector('.btn-modal-ok').textContent=label;document.getElementById('modal-overlay').classList.add('aberto')}
function fecharModal(){if(baixando)return;document.getElementById('modal-overlay').classList.remove('aberto');itemParaBaixa=null}
document.getElementById('modal-overlay').addEventListener('click',e=>{if(e.target===e.currentTarget)fecharModal()});
async function confirmarBaixa(){if(!itemParaBaixa||baixando)return;const item=itemParaBaixa;const dados={id:item.id};if(modoModal==='mudar_morador')dados.confirmacao=document.getElementById('confirmacao-unidade').value.trim();if(modoModal==='devolver'){dados.observacao=document.getElementById('motivo-devolucao').value.trim();if(dados.observacao.length<5)return toast('Informe o motivo da devolução.')}
 baixando=true;const btn=document.querySelector('.btn-modal-ok');btn.disabled=true;try{await Portal.call(modoModal,dados);baixando=false;fecharModal();toast(modoModal==='mudar_morador'?'Mudança registrada. Apartamento liberado.':'Operação registrada.','green');await exibirVisaoPorteiro();if(document.getElementById('cadastros-moradores').open)await carregarMoradores()}catch(e){toast(e.message)}finally{baixando=false;btn.disabled=false}}
async function carregarMoradores(){const box=document.getElementById('lista-moradores');try{window.moradoresGlobal=await Portal.call('moradores');const busca=(document.getElementById('busca-moradores').value||'').toLowerCase();box.innerHTML=window.moradoresGlobal.filter(m=>(m.nome+' '+m.bloco+'-'+m.apartamento).toLowerCase().includes(busca)).map(m=>'<div class="item-pendente"><div class="item-info"><div class="item-apto">'+Portal.escape(m.bloco+'-'+m.apartamento)+'</div><div class="item-nome">'+Portal.escape(m.nome)+'</div></div><button class="btn-xls" data-mudanca="'+m.id+'">Morador se mudou</button></div>').join('')||'<p>Nenhum cadastro encontrado.</p>';box.querySelectorAll('[data-mudanca]').forEach(btn=>btn.onclick=()=>{const m=window.moradoresGlobal.find(m=>String(m.id)===btn.dataset.mudanca);modoModal='mudar_morador';itemParaBaixa=m;prepararModal('Morador se mudou',m.bloco+'-'+m.apartamento,m.nome,'<label for="confirmacao-unidade">Digite '+Portal.escape(m.bloco+'-'+m.apartamento)+' para confirmar</label><input id="confirmacao-unidade" autocomplete="off">','Confirmar mudança')})}catch(e){box.textContent=e.message}}
async function carregarSolicitacoes(){const box=document.getElementById('lista-solicitacoes');try{const data=await Portal.call('solicitacoes');box.innerHTML=data.map(s=>'<div class="item-pendente"><div class="item-info"><div class="item-apto">'+Portal.escape(s.bloco+'-'+s.apartamento)+'</div><div class="item-nome">'+Portal.escape(s.nome)+'</div><div>'+Portal.escape(s.whatsapp)+'</div></div><button class="btn-xls" data-aprovar="'+s.id+'">Aprovar</button><button class="btn-xls" data-rejeitar="'+s.id+'">Rejeitar</button></div>').join('')||'<p>Nenhum cadastro aguardando conferência.</p>';for(const [attr,acao] of [['data-aprovar','aprovar'],['data-rejeitar','rejeitar']])box.querySelectorAll('['+attr+']').forEach(btn=>btn.onclick=async()=>{if(!confirm(acao==='aprovar'?'Conferiu os dados com o morador e deseja aprovar?':'Rejeitar esta solicitação?'))return;btn.disabled=true;try{await Portal.call(acao,{id:btn.getAttribute(attr)});await carregarSolicitacoes();await exibirVisaoPorteiro()}catch(e){toast(e.message)}finally{btn.disabled=false}})}catch(e){box.textContent=e.message}}
document.getElementById('cadastros-moradores').addEventListener('toggle',e=>{if(e.target.open)carregarMoradores()});
document.getElementById('cadastros-solicitacoes').addEventListener('toggle',e=>{if(e.target.open)carregarSolicitacoes()});
document.getElementById('busca-moradores').addEventListener('input',carregarMoradores);
async function exibirVisaoMorador(){try{const e=await Portal.call('ver_encomenda',{},encomendaToken);if(e.status==='ENTREGUE')return mostrarSucesso();if(e.status==='DIVERGÊNCIA'){document.getElementById('conteudo-pendente').classList.add('hidden');document.getElementById('conteudo-engano').classList.remove('hidden');return}if(e.status!=='DISPONÍVEL')throw Error('Esta encomenda não está disponível para confirmação. Procure a portaria.');document.getElementById('detalhe-encomenda').textContent=e.nome+', confirme a retirada de '+e.quantidade+' volume(s) para '+e.bloco+'-'+e.apartamento+' somente após receber na portaria.'}catch(e){document.getElementById('detalhe-encomenda').textContent=e.message;document.querySelectorAll('#conteudo-pendente button').forEach(btn=>btn.disabled=true)}}
let confirmandoMorador=false;
async function acaoMorador(acao){if(confirmandoMorador)return;confirmandoMorador=true;document.querySelectorAll('#conteudo-pendente button').forEach(btn=>btn.disabled=true);try{await Portal.call(acao,{},encomendaToken);await exibirVisaoMorador()}catch(e){toast(e.message);document.querySelectorAll('#conteudo-pendente button').forEach(btn=>btn.disabled=false)}finally{confirmandoMorador=false}}
function confirmarPeloMorador(){return acaoMorador('confirmar_retirada')}
function registrarEngano(){return acaoMorador('informar_engano')}
function mostrarSucesso(){document.getElementById('conteudo-pendente').classList.add('hidden');document.getElementById('conteudo-sucesso').classList.remove('hidden')}
function enviarWppPortaria(){}
async function exportarXLS(){try{const rows=[];for(let offset=0;;offset+=500){const data=await Portal.call('historico',{offset});rows.push(...data);if(data.length<500)break}const q=v=>'"'+String(v??'').replace(/^[=+\-@\t\r]/,"'").replace(/"/g,'""')+'"';const text='\ufeff'+[['Entrada','Bloco','Apto','Nome','Volumes','Status','Retirada'],...rows.map(e=>[e.criado_em,e.bloco,e.apartamento,e.nome,e.quantidade,e.status,e.baixado_em])].map(r=>r.map(q).join(';')).join('\r\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8'}));a.download='encomendas_agua_marinha.csv';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),30000)}catch(e){toast(e.message)}}

    function renderLista(data) {
        const cont = document.getElementById('lista-pendentes');

        if (!data || data.length === 0) {
            cont.innerHTML = `
                <div class="lista-vazia">
                    <svg fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                    <p>Nenhuma encomenda aguardando retirada</p>
                </div>`;
            return;
        }

        // Agrupar por data
        const hoje = new Date();
        const grupos = {};

        data.forEach(item => {
            const d = new Date(item.criado_em);
            const chave = d.toLocaleDateString('pt-BR');
            if (!grupos[chave]) grupos[chave] = { label: '', items: [], data: d };
            grupos[chave].items.push(item);
        });

        // Labels legíveis
        Object.keys(grupos).forEach(chave => {
            const g = grupos[chave];
            const diff = Portal.dias(g.data);
            if (diff === 0) g.label = 'Hoje';
            else if (diff === 1) g.label = 'Ontem';
            else g.label = `${chave} · ${diff} dias atrás`;
            g.diasAtraso = diff;
        });

        let html = '';
        Object.keys(grupos).sort((a,b) => grupos[a].data - grupos[b].data).forEach(chave => {
            const g = grupos[chave];
            const atrasado = g.diasAtraso >= 3;
            html += `<div class="dia-grupo">
                <div class="dia-label ${atrasado ? 'atrasado' : ''}">${g.label}</div>`;

            g.items.forEach(item => {
                const m = item.moradores || {nome:'Cadastro indisponível',bloco:'?',apartamento:'?'};
                const apto = `${m.bloco}-${m.apartamento}`;
                const iniciais = m.nome.trim().split(' ').slice(0,2).map(p => p[0]).join('');
                const avClass = g.diasAtraso >= 5 ? 'muito-atrasado' : g.diasAtraso >= 3 ? 'atrasado' : '';
                const hora = new Date(item.criado_em).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

                html += `
                    <div class="item-pendente">
                        <div class="item-av ${avClass}">${Portal.escape(iniciais)}</div>
                        <div class="item-info">
                            <div class="item-apto">${Portal.escape(apto)}</div>
                            <div class="item-nome">${Portal.escape(m.nome)}</div>
                            <div class="item-meta">
                                <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                ${hora}
                            </div>
                        </div>
                        <span class="vol-badge">${item.quantidade} vol.</span>${item.status==='DIVERGÊNCIA'?'<strong>Conferir destinatário</strong>':''}
                        <button class="btn-baixa" data-baixa="${Portal.escape(item.id)}">Retirada</button><button class="btn-xls" data-aviso="${Portal.escape(item.id)}">Avisar</button><button class="btn-xls" data-devolver="${Portal.escape(item.id)}">Devolver</button>
                    </div>`;
            });

            html += '</div>';
        });

        cont.innerHTML = html;
        cont.querySelectorAll('[data-baixa]').forEach(btn=>btn.onclick=()=>abrirModalById(btn.dataset.baixa));
        cont.querySelectorAll('[data-aviso]').forEach(btn=>btn.onclick=()=>avisar(btn.dataset.aviso));
        cont.querySelectorAll('[data-devolver]').forEach(btn=>btn.onclick=()=>devolver(btn.dataset.devolver));
    }


inicializar().catch(e=>mostrarLogin(e.message));