# Portal Água Marinha — acesso simples

## Fluxo acordado
- Porteiro: mesma tela e uma senha, sem e-mail ou conta individual. Seleciona bloco/apartamento, volumes e registra; o WhatsApp abre na sequência e precisa ter o envio concluído pelo porteiro.
- Morador: nome, bloco, apartamento e WhatsApp. Sem senha, e-mail ou conta. A portaria confere a solicitação.
- Encomenda: link aleatório específico para o volume, com prazo de 30 dias; o link nunca dá acesso a uma lista de moradores.
- Mudança: portaria abre “Moradores e mudanças”, escolhe “Morador se mudou” e confirma a unidade. Encomendas pendentes impedem a saída. Cadastro antigo e histórico são preservados. Novo morador recebe novo ID.
- Administração: somente o administrador usa e-mail. Configura a senha da portaria uma vez (pode reutilizar a senha conhecida se atender aos 8 caracteres mínimos).

## Segurança
Senha da portaria verificada no servidor com bcrypt. Sessões opacas aleatórias de 256 bits, armazenadas por hash no banco e com validade de 12 horas. Logout e troca de senha revogam sessões. Em acesso compartilhado não é possível atribuir uma operação a um porteiro específico; auditoria registra a sessão, sem inventar uma identidade individual.

Links também usam 256 bits e hash no banco, são restritos a uma encomenda e deixam de funcionar após a mudança. Token fica no fragmento da URL, com referrer desativado. Link antigo sem token não é aceito. Reenvio de aviso revoga o link anterior. A posse do link autoriza a confirmação, sem provar a identidade de quem clicou.

O gateway Edge `portal-simples` verifica a sessão ou o token em cada operação. `verify_jwt=false` é intencional: moradores não têm conta Auth; a autenticação ocorre pelo próprio gateway. A RPC interna só é executável por service_role. O frontend não recebe essa chave. Há limitação de tentativas e validação no servidor.

Baixa simples não exige um campo novo nem inventa o nome de quem retirou. Devolução pede motivo. Engano sinaliza DIVERGÊNCIA em vez de entrega.

## Estado e publicação
As duas migrações anteriores de estrutura/API já existem no banco. **A migração nova de acesso simples não foi aplicada:** a revisão automática rejeitou uma alteração persistente da autenticação em produção sem aprovação específica. Também não foi feito o corte do frontend nem o bloqueio das políticas anônimas antigas.

A implementação nova está neste PR para teste e aprovação. A versão atualmente em `/nova-versao/` ainda corresponde ao fluxo anterior com e-mail e será substituída somente após a preparação do servidor. Não orientar porteiros ou moradores a criar contas nela.

Sequência de publicação após aprovação:
1. Aplicar a migração de acesso simples.
2. Publicar a Edge Function e testar negativas de senha, sessão e token.
3. Administrador cria/confirma seu único login e configura a senha conhecida da portaria em “Senha da portaria”. Não pedir a senha no chat.
4. Testar o login da portaria e o recebimento em unidade autorizada.
5. Publicar as páginas simples e aplicar o bloqueio do acesso direto anônimo no mesmo corte.
6. Reenviar os avisos antigos ainda pendentes para gerar os novos links protegidos.

Não foi apagado nenhum cadastro. As antigas políticas abertas permanecem até o corte; a segurança de produção ainda não está concluída.

## Testes
O workflow usa PostgreSQL isolado, aplica o esquema e testa a migração nova; não usa dados de produção nem envia mensagens. Testa senha, hashes, rate limit, sessão, idempotência, isolamento por token, baixa sem campos novos, mudança e histórico.
O teste Playwright usa gateway simulado e verifica o fluxo familiar, ausência de e-mail para porteiros/moradores, WhatsApp, confirmação, mudança e uso no celular.

Para desenvolvimento: `npm ci`, `npx playwright install chromium`, `npm run check`, `npm test`. O SQL está em `tests/acesso-simples.sql`; requer o esquema de teste mais as três migrações indicadas no workflow.
