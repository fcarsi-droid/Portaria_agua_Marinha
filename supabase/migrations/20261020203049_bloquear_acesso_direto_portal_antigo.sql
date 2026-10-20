-- Corte autorizado para o portal simples: acesso a dados somente pelas funções protegidas.
alter table public.moradores enable row level security;
alter table public.encomendas enable row level security;
drop policy if exists leitura_encomendas on public.encomendas;
drop policy if exists baixa_encomendas on public.encomendas;
drop policy if exists registro_encomendas_v2 on public.encomendas;
drop policy if exists leitura_publica_moradores on public.moradores;
drop policy if exists cadastro_moradores on public.moradores;
revoke all privileges on table public.moradores,public.encomendas from public,anon,authenticated;
revoke all privileges on sequence public.moradores_id_seq,public.encomendas_id_seq from public,anon,authenticated;
