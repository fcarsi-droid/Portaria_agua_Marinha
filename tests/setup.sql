
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema extensions;
create extension pgcrypto with schema extensions;
create function auth.uid() returns uuid language sql stable as $$ select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid; $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb; $$;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id),not_after timestamptz);
create table public.moradores(id serial primary key,bloco text not null,apartamento text not null,nome text not null,whatsapp text not null, constraint moradores_bloco_apartamento_key unique(bloco,apartamento));
create table public.encomendas(id serial primary key,morador_id integer references public.moradores(id),quantidade integer default 1,criado_em timestamptz default now(),status text default 'DISPONÍVEL',baixado_pela text,baixado_em timestamptz);
alter table public.moradores enable row level security;
alter table public.encomendas enable row level security;
grant usage on schema public,auth to anon,authenticated,service_role;
