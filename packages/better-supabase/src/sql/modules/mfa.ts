import type { ModuleDefinition } from "../module-types.ts";

import { SCHEMA } from "../shared.ts";

export const MFA: ModuleDefinition = {
  internal: ["mfa_satisfied"],
  name: "mfa",
  title: "MFA enforcement",
  description:
    "mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).",
  requires: [],
  target: "schema",
  build: () => `${SCHEMA}

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
--   with check ((select better_supabase.mfa_satisfied()));`,
};
