# Portal Água Marinha

Versão simples publicada no endereço principal https://portalaguamarinha.com.br após autorização do proprietário.

- Portaria: senha compartilhada configurada na administração; sem e-mail. Registra encomendas, dá baixa e informa mudanças.
- Morador se mudou: opção no início da tela. Desativa o cadastro, libera a unidade e preserva o histórico. Pendências precisam ser resolvidas antes.
- Cadastro de moradores: nome, bloco, apartamento e WhatsApp; aprovação exclusiva da administração.
- Administração: conta de e-mail do responsável, com configuração da senha da portaria.
- Avisos pelo WhatsApp: o porteiro conclui o envio; cada encomenda recebe um link protegido. O portal não comprova entrega da mensagem.
- Regra autorizada pela síndica em 21/10/2026: avisos de novas remessas são suspensos quando há mais de 10 remessas DISPONÍVEL sem baixa e a mais antiga já completou 4 dias. Dez pendências não bloqueiam; a 11ª é registrada e já não gera aviso se o prazo estiver cumprido. A contagem é de registros de remessa, não volumes. Entregues, devolvidas e divergências não entram.

A raiz contém a única versão mantida do portal. A regra anterior proposta não foi publicada; a regra autorizada de 21/10/2026 está descrita acima. Histórico anterior: commit 9cb7b58de5c3fb1324d7940d7383c664034a22b8. Nenhuma senha foi alterada pela publicação.

O teste tests/publicacao.cjs verifica o endereço principal e o gateway sem criar dados nem enviar mensagens.

O corte do acesso direto antigo foi concluído pela migração 20261020203049_bloquear_acesso_direto_portal_antigo. As tabelas moradores e encomendas permanecem com RLS e sem privilégios diretos para anon/authenticated; as funções autenticadas da portaria e administração foram verificadas após o corte. Nenhum registro foi removido. Os endereços antigos em /nova-versao/ redirecionam para a raiz e preservam os parâmetros e o fragmento da URL, incluindo tokens de encomendas e recuperação de acesso.

Validação da publicação: https://github.com/fcarsi-droid/Portaria_agua_Marinha/actions/runs/39492330743. Acesso direto negado e consultas de portaria/administração validadas em transação revertida no banco.

## Links antigos
A pasta nova-versao contém apenas index.html, portaria.html, cadastro.html e admin.html, com redirecionamento para a página correspondente na raiz. Não há scripts, estilos ou bibliotecas duplicados. Não remover esses redirecionamentos enquanto houver links antigos em circulação.

## Acesso da portaria
A sessão é persistida em localStorage, migrando a sessão da aba existente. No servidor, sessões válidas têm 30 dias e são renovadas durante o uso, no máximo uma atualização de prazo por dia. Apenas sessões ainda válidas foram prorrogadas na implantação; expiradas ou revogadas não são reativadas. Logout e troca da senha continuam revogando o acesso. Erros temporários de conexão não removem a sessão. Usar navegação normal do navegador; limpeza dos dados do site remove o acesso salvo.

O bloqueio é validado no servidor para a portaria e para a administração. Registros e baixas continuam funcionando; links válidos anteriores permitem regularizar. Lembretes de regularização continuam disponíveis. O horário de registro do recebimento/aviso inicial é usado para avaliar os quatro dias, em intervalos de 96 horas; o portal não comprova entrega externa da mensagem no WhatsApp.

Implantação concluída na migração 20261022000300_bloqueio_11_remessas_4_dias_e_sessao_persistente. Os testes de banco são executados com BEGIN/ROLLBACK explícito e não deixam moradores, remessas ou sessões de teste persistidos. Verificações da interface: https://github.com/fcarsi-droid/Portaria_agua_Marinha/actions/runs/39697118489

## Prevenção de repetição
O servidor identifica registro da mesma operação e impede duplicação por repetição de requisição. Para o mesmo morador e quantidade de volumes, um registro pendente dos últimos cinco minutos exige confirmação explícita de que é outra encomenda. A verificação é serializada por morador e funciona também na administração. O aviso mostra o número e horário do registro existente, oferece reenvio e não cria nem invalida links automaticamente na tentativa duplicada. A portaria também mostra o último registro pendente ao selecionar a unidade. Não há confirmação automática de envio pelo WhatsApp nem identificação física de volumes: entregas distintas podem ter a mesma quantidade.
