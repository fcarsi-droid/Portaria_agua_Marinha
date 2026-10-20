# Portal Água Marinha

Versão simples publicada no endereço principal https://portalaguamarinha.com.br após autorização do proprietário.

- Portaria: senha compartilhada configurada na administração; sem e-mail. Registra encomendas, dá baixa e informa mudanças.
- Morador se mudou: opção no início da tela. Desativa o cadastro, libera a unidade e preserva o histórico. Pendências precisam ser resolvidas antes.
- Cadastro de moradores: nome, bloco, apartamento e WhatsApp; aprovação exclusiva da administração.
- Administração: conta de e-mail do responsável, com configuração da senha da portaria.
- Avisos pelo WhatsApp: o porteiro conclui o envio; cada encomenda recebe um link protegido. O portal não comprova entrega da mensagem.
- A suspensão de avisos por pendências NÃO foi autorizada e NÃO está ativa nesta versão.

A raiz contém a única versão mantida do portal. A proposta de suspensão da branch de melhorias não está publicada. Histórico anterior: commit 9cb7b58de5c3fb1324d7940d7383c664034a22b8. Nenhuma senha foi alterada pela publicação.

O teste tests/publicacao.cjs verifica o endereço principal e o gateway sem criar dados nem enviar mensagens.

O corte do acesso direto antigo foi concluído pela migração 20261020203049_bloquear_acesso_direto_portal_antigo. As tabelas moradores e encomendas permanecem com RLS e sem privilégios diretos para anon/authenticated; as funções autenticadas da portaria e administração foram verificadas após o corte. Nenhum registro foi removido. Os endereços antigos em /nova-versao/ redirecionam para a raiz e preservam os parâmetros e o fragmento da URL, incluindo tokens de encomendas e recuperação de acesso.

Validação da publicação: https://github.com/fcarsi-droid/Portaria_agua_Marinha/actions/runs/39492330743. Acesso direto negado e consultas de portaria/administração validadas em transação revertida no banco.

## Links antigos
A pasta nova-versao contém apenas index.html, portaria.html, cadastro.html e admin.html, com redirecionamento para a página correspondente na raiz. Não há scripts, estilos ou bibliotecas duplicados. Não remover esses redirecionamentos enquanto houver links antigos em circulação.
