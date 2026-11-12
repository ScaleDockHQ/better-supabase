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



