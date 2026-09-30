-- Fixture schema for tests, examples and codegen. It exercises every feature
-- better-supabase generates types for: enums, CHECK unions, jsonb, composite
-- keys, forward and reverse relations, soft delete, timestamps and RLS.

create type public.note_kind as enum ('call', 'meeting', 'email');

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(auth.jwt() ->> 'tenant_id', '')::uuid
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
