# Portal de encomendas — Água Marinha

Aplicação estática em HTML/CSS/JavaScript com Supabase Auth e operações autorizadas no PostgreSQL. Sem servidor local obrigatório para o usuário; hospedagem atual no GitHub Pages é preservada.

## O que mudou

- Central da portaria com recebimento, busca sem acentos, filtro de atraso, WhatsApp explícito, retirada com nome do recebedor e devolução com motivo.
- Mudança de morador: desativa o cadastro e libera a unidade, mantendo o ID e o histórico do antigo destinatário. Encomendas disponíveis ou em divergência impedem a saída até serem resolvidas.
- Novo morador cria sua conta e solicita vínculo; portaria confere e aprova. O cadastro ativo do antigo morador nunca é sobrescrito. Cadastros legados podem ser vinculados ao mesmo morador mediante confirmação da portaria.
- Login individual, confirmação de e-mail, recuperação de senha e permissões consultadas no servidor. Equipe desativada perde a autorização imediatamente. Antigo morador não vê a unidade mesmo com JWT ainda válido.
- Histórico completo paginado, relatório CSV compatível com Excel e indicadores com registros próximos para conferência, retiradas por origem e unidades com pendências.
- Engano gera DIVERGÊNCIA, não uma falsa entrega; portaria confere o destinatário ou devolve fisicamente o volume.
- Registro idempotente, validações no servidor, transações e bloqueios por destinatário para proteger contra operações simultâneas.
- SDK Supabase 2.118.0 mantido no próprio repositório para evitar falha de CDN em uso diário; chave publishable é pública por definição. Nunca usar service_role no frontend.

## Estado da implantação

As migrações `20261020154639` e `20261020154817` foram aplicadas ao projeto conectado. Elas adicionam campos e a API segura sem remover os dados existentes. A conta inicial de administrador foi configurada privadamente com o e-mail escolhido pelo proprietário; a pessoa ainda deve criar a conta pelo Auth e confirmar seu e-mail.

**A migração `bloquear_acesso_anonimo` ainda não foi aplicada.** Ela bloqueia o acesso usado pelo frontend antigo, por isso deve ser aplicada no corte coordenado para esta versão. Até o corte, as políticas antigas continuam abertas. Não considerar a segurança de produção concluída antes dessa etapa.

## Antes de publicar

1. Em Supabase → Authentication → URL Configuration, configurar Site URL `https://portalaguamarinha.com.br` (domínio canônico observado) e permitir os redirects `https://portalaguamarinha.com.br/cadastro.html` e `https://portalaguamarinha.com.br/nova-versao/cadastro.html`; incluir também as duas variantes com `www` enquanto forem usadas.
2. Em Authentication → Email, verificar envio de confirmação e recuperação. O serviço de e-mail padrão do Supabase pode aceitar somente endereços autorizados da equipe e possui limites baixos. Configurar SMTP próprio antes de liberar cadastro para todos os moradores. Não desabilitar confirmação para contornar isso.
3. A versão de validação foi disponibilizada em `/nova-versao/`, sem substituir as páginas atuais. Usar os redirects descritos no item 1. A versão de validação usa o banco real; operações são reais, não uma demonstração com dados fictícios. Criar/confirmar a conta inicial nessa versão. O e-mail foi escolhido pelo proprietário e está em tabela privada; não há senha inicial no código.
4. Confirmar login do administrador, testar portaria e aprovação com uma unidade autorizada para homologação.
5. Publicar os arquivos de aplicação juntos e aplicar a migração de corte. Verificar que leituras REST anônimas de moradores/encomendas falham, que login funciona e que registros antigos foram preservados.
6. Cada membro da portaria cria e confirma a própria conta. Administrador libera seu e-mail na aba Equipe.

Se a confirmação de e-mail apontar para uma URL antiga, o vínculo pode já ter sido confirmado no Auth. Corrigir URL Configuration e testar novamente a navegação. Não afirmar que o envio de e-mails funciona sem verificar recebimento.

## Segurança e permissões

A API pública é `public.portal`, `SECURITY INVOKER`, executável somente por `authenticated`. Ela encaminha para a função privada `portal_private.executar`, que exige `auth.uid()`, usuário com e-mail confirmado, sessão não revogada e papel/pertencimento válido para cada ação. O schema privado não deve ser incluído na lista de schemas expostos do Data API.

A função privada é `SECURITY DEFINER` deliberadamente, com `search_path` vazio e nomes qualificados. Permite somente operações pré-definidas, sem SQL dinâmico. Não se usa `user_metadata` para autorização. Tabelas privadas têm RLS sem políticas e sem grants diretos ao cliente; isso é intencional (acesso negado fora da API), não uma ausência acidental de proteção. [Explicação do aviso informativo do Advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

A retirada/devolução/mudança registra autor e horário. Não se apagam permanentemente moradores, encomendas ou usuários Auth. Sessões do browser ficam em sessionStorage e são removidas no logout. A saída do morador corta imediatamente seu acesso à unidade via banco, embora a conta pessoal continue existindo para eventual novo cadastro aprovado.

## Testes

`tests/banco.sql` executa uma transação com usuários fictícios e termina em ROLLBACK. Testa idempotência, quantidades, isolamento de contas, divergência, bloqueio de saída com pendências, confirmação de unidade, revogação de acesso após saída, aprovação de novo morador com novo ID e preservação do histórico, além de revogação da equipe e sessão. Executado com sucesso no banco conectado, sem usuários ou dados fictícios persistentes (sequências podem ter lacunas).

Interface: `npm ci`, `npx playwright install chromium`, `npm run check`, `npm test`. Testes usam banco simulado, sem acesso aos dados de produção. Incluem telas desktop/mobile, filtro, WhatsApp, dupla submissão, retirada, mudança bloqueada e liberada, morador, divergência e escape de HTML. O workflow do GitHub executa a verificação e guarda capturas de tela.

O ambiente local restringiu sockets do Chromium; os testes de navegador passaram no GitHub Actions, em computador e celular. Validação de sintaxe e testes reais transacionais do banco também passaram. A execução inicial está em https://github.com/fcarsi-droid/Portaria_agua_Marinha/actions/runs/39452765495.

## Limites conhecidos

- Cadastro de pessoas depende de confirmação de e-mail e SMTP configurado. Envio de WhatsApp é manual pelo aplicativo do porteiro, sem confirmação automática de entrega.
- Lista do morador mostra os últimos 300 registros. A portaria tem histórico e exportação completos.
- Paginação por offset pode sofrer alterações entre páginas se houver novos registros simultâneos. Para auditoria fechada, gerar relatório em período de pouca movimentação ou evoluir para fotografia transacional.
- O export atual é CSV UTF-8 com separador `;`, abre no Excel. Não é XLSX.
- Rótulos e filtros de idade usam dias de calendário do dispositivo; dispositivos devem estar com fuso/relógio corretos.
- Antes de coletar mais dados de moradores, definir política de retenção e necessidade; esta revisão preserva os dados históricos existentes.
