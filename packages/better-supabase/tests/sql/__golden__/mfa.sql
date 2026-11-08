-- ==== alone: schema supabase/schemas/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block mfa@1 managed
-- @bsb-hash sha256:0bd35c21011ed7869a7931def9caa5689fc9c5a05e188e172e45fdd73aa99403
-- mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- authenticated can't read auth.mfa_factors, so the check runs as the owner.
create or replace function better_supabase.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    or not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = auth.uid()
        and f.status = 'verified'
    )
$$;

revoke execute on function better_supabase.mfa_satisfied() from public, anon;
grant execute on function better_supabase.mfa_satisfied() to authenticated;

-- Restrictive, so it applies on top of the table's other policies:
-- create policy mfa_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.mfa_satisfied()))
--   with check ((select better_supabase.mfa_satisfied()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block-data mfa
-- @bsb-hash sha256:9d4b5127d519e3599828ad8e00823159b8b2ab5ac1a9e736125a63a738f7c611
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mfa', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block mfa@1 managed
-- @bsb-hash sha256:0bd35c21011ed7869a7931def9caa5689fc9c5a05e188e172e45fdd73aa99403
-- mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- authenticated can't read auth.mfa_factors, so the check runs as the owner.
create or replace function better_supabase.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    or not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = auth.uid()
        and f.status = 'verified'
    )
$$;

revoke execute on function better_supabase.mfa_satisfied() from public, anon;
grant execute on function better_supabase.mfa_satisfied() to authenticated;

-- Restrictive, so it applies on top of the table's other policies:
-- create policy mfa_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.mfa_satisfied()))
--   with check ((select better_supabase.mfa_satisfied()));

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block-data mfa
-- @bsb-hash sha256:9d4b5127d519e3599828ad8e00823159b8b2ab5ac1a9e736125a63a738f7c611
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mfa', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block mfa@1 managed
-- @bsb-hash sha256:0bd35c21011ed7869a7931def9caa5689fc9c5a05e188e172e45fdd73aa99403
-- mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- authenticated can't read auth.mfa_factors, so the check runs as the owner.
create or replace function better_supabase.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    or not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = auth.uid()
        and f.status = 'verified'
    )
$$;

revoke execute on function better_supabase.mfa_satisfied() from public, anon;
grant execute on function better_supabase.mfa_satisfied() to authenticated;

-- Restrictive, so it applies on top of the table's other policies:
-- create policy mfa_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.mfa_satisfied()))
--   with check ((select better_supabase.mfa_satisfied()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block-data mfa
-- @bsb-hash sha256:9d4b5127d519e3599828ad8e00823159b8b2ab5ac1a9e736125a63a738f7c611
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mfa', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block mfa@1 managed
-- @bsb-hash sha256:521b887109eba4f4b0ce9ed57c698ba856699512841cea307f4a80f4762db0e2
-- mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- authenticated can't read auth.mfa_factors, so the check runs as the owner.
create or replace function better_supabase.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    or not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = auth.uid()
        and f.status = 'verified'
    )
$$;

revoke execute on function better_supabase.mfa_satisfied() from public, anon;
grant execute on function better_supabase.mfa_satisfied() to authenticated;

-- Restrictive, so it applies on top of the table's other policies:
-- create policy mfa_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.mfa_satisfied()))
--   with check ((select better_supabase.mfa_satisfied()));

-- blocks.mfa.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.




-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_015_mfa.sql
-- better-supabase module: mfa
-- @bsb-block-data mfa
-- @bsb-hash sha256:9d4b5127d519e3599828ad8e00823159b8b2ab5ac1a9e736125a63a738f7c611
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mfa', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
