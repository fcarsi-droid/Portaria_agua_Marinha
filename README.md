# Portal Água Marinha — acesso simples

## Fluxo acordado
- Porteiro: mesma tela e uma senha, sem e-mail ou conta individual. Seleciona bloco/apartamento, volumes e registra; o WhatsApp abre na sequência e precisa ter o envio concluído pelo porteiro.
- Morador: nome, bloco, apartamento e WhatsApp. Sem senha, e-mail ou conta. A administração confere e aprova a solicitação.
- Encomenda: link aleatório específico para o volume, com prazo de 30 dias; o link nunca dá acesso a uma lista de moradores.
- Mudança: portaria abre “Morador se mudou” no alto da tela, escolhe “Morador se mudou” e confirma a unidade. Encomendas pendentes impedem a saída. Cadastro antigo e histórico são preservados. Novo morador recebe novo ID.
- Administração: somente o administrador usa e-mail. Configura a senha da portaria uma vez (pode reutilizar a senha conhecida se atender aos 8 caracteres mínimos).

## Suspensão de avisos por pendências
Implementação preparada e validada em banco isolado e navegador. Ainda não aplicada ao banco de produção: revisão automática exigiu autorização explícita do proprietário para alterar as funções e bloquear avisos de moradores reais. A prévia publicada ainda não aplica a suspensão.

A partir de 10 registros de recebimento DISPONÍVEL do mesmo morador, cada um com mais de 10 dias corridos (240 horas), o servidor deixa de emitir novos links de aviso. Conta recebimentos, não a soma de volumes. ENTREGUE, DEVOLVIDA e DIVERGÊNCIA não entram na contagem; divergência depende de conferência da portaria.

O registro de novas encomendas e todas as baixas continuam funcionando. Avisos voltam automaticamente quando restarem menos de 10 registros nessa condição. Links válidos emitidos antes da suspensão continuam permitindo a baixa; um link expirado exige conferência com a portaria. A regra é consultada a cada emissão, nas listagens e na atualização da portaria a cada minuto quando a tela está visível.

Portaria e administração mostram o alerta e um botão específico para preparar a mensagem de suspensão no WhatsApp. A mensagem precisa ser enviada pelo porteiro; abrir o link não comprova entrega. O portal não usa API automática de WhatsApp.

A suspensão vale na nova versão. A raiz antiga continua operando até o corte coordenado.

## Segurança
Senha da portaria verificada no servidor com bcrypt. Sessões opacas aleatórias de 256 bits, armazenadas por hash no banco e com validade de 12 horas. Logout e troca de senha revogam sessões. Em acesso compartilhado não é possível atribuir uma operação a um porteiro específico; auditoria registra a sessão, sem inventar uma identidade individual.

Links também usam 256 bits e hash no banco, são restritos a uma encomenda e deixam de funcionar após a mudança. Token fica no fragmento da URL, com referrer desativado. Link antigo sem token não é aceito. Reenvio de aviso revoga o link anterior. A posse do link autoriza a confirmação, sem provar a identidade de quem clicou.

O gateway Edge `portal-simples` verifica a sessão ou o token em cada operação. `verify_jwt=false` é intencional: moradores não têm conta Auth; a autenticação ocorre pelo próprio gateway. A RPC interna só é executável por service_role. O frontend não recebe essa chave. Há limitação de tentativas e validação no servidor.

Baixa simples não exige um campo novo nem inventa o nome de quem retirou. Devolução pede motivo. Engano sinaliza DIVERGÊNCIA em vez de entrega.

## Estado e publicação

A migração de acesso simples foi autorizada pelo proprietário e aplicada em produção em 20/10/2026 (versão 20261020173843). A Edge Function `portal-simples` está publicada. A prévia em `/nova-versao/` foi atualizada com os formulários simples. O portal principal permanece na versão anterior até concluir a validação da senha.

Os dados existentes foram preservados: 104 moradores e 5.784 encomendas na conferência após a migração. O banco continua recebendo movimentação normal.

Ainda falta **uma configuração pelo administrador**, sem senha no chat:
1. Entrar em `/nova-versao/admin.html` com a conta do administrador já confirmada.
2. Abrir “Senha da portaria” e definir a senha que será usada pela equipe. Porteiros não criam conta por e-mail.
3. Testar essa senha em `/nova-versao/portaria.html`.
4. Somente após a validação, publicar as páginas simples na raiz e aplicar o bloqueio das políticas anônimas antigas no mesmo corte.

O retorno de confirmação e recuperação de senha do administrador aponta para `admin.html`, separado do formulário público dos moradores. Conferir em Authentication → URL Configuration os endereços `https://portalaguamarinha.com.br/nova-versao/admin.html` e a variante com www, além do endereço de produção `/admin.html`. Confirmação e recuperação dependem de entrega de e-mails do Supabase.

Nenhum cadastro foi apagado. As políticas anônimas antigas permanecem ativas até o corte; não considerar a segurança da versão principal concluída antes dessa etapa. Após o corte, avisos antigos ainda pendentes devem ser reenviados para receber o link protegido.

## Testes
O workflow usa PostgreSQL isolado, aplica o esquema e testa a migração nova; não usa dados de produção nem envia mensagens. Testa senha, hashes, rate limit, sessão, idempotência, isolamento por token, baixa sem campos novos, mudança e histórico.
O teste Playwright usa gateway simulado e verifica o fluxo familiar, ausência de e-mail para porteiros/moradores, WhatsApp, confirmação, mudança e uso no celular.

Para desenvolvimento: `npm ci`, `npx playwright install chromium`, `npm run check`, `npm test`. Os testes SQL estão em `tests/acesso-simples.sql` e `tests/suspensao-avisos.sql`; usam o esquema isolado e as migrações indicadas no workflow. A suspensão verifica limites de quantidade e idade, status, isolamento entre unidades, registro idempotente, bloqueio também para o administrador e desbloqueio por baixa. Playwright verifica alerta, mensagem de suspensão e retorno do aviso normal.

## Responsabilidades de cadastro
Somente a administração lista, aprova ou rejeita solicitações. A sessão compartilhada da portaria recebe 403 nessas ações. A portaria registra mudanças no cartão “Morador se mudou”, antes de Nova Encomenda; não aprova novos moradores. Migração 20261020183541 aplicada e validada. A suspensão de avisos permanece não autorizada e não aplicada.
