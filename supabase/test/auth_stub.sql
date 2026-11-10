-- Local stand-in for Supabase's auth schema, so schema.sql can be tested on plain Postgres.
-- See supabase/test/README.md. NEVER run this on your real Supabase project.
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create role authenticated nologin;
grant usage on schema public, auth to authenticated;
alter default privileges in schema public grant all on tables to authenticated;
insert into auth.users values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222');
