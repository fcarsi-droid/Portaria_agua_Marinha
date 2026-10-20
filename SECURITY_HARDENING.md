# Segurança do portal

Consulte README.md para arquitetura, implantação e limitações. A segurança nova só fica efetiva em produção após a publicação do frontend e a migração `bloquear_acesso_anonimo` no mesmo corte.

Não exponha `portal_private` no Data API e não conceda acesso direto às tabelas ao cliente. Não publique chaves secret/service_role. A chave publishable do frontend é pública, protegida por autorização no banco.

O cadastro legado e a relação das encomendas não são apagados na mudança de morador. O novo cadastro recebe um novo ID; histórico não é transferido.
