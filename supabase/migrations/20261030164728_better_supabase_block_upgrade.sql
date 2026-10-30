-- better-supabase upgrade: steps that run before the schema diff.

-- compliance: version 1 to 2. Policy acknowledgements move onto the acknowledgements block: each policy_acknowledgements row becomes an acknowledgement of the policy's version, every live policy that requires acknowledgement is assigned to the member role, and policy_acknowledgements, acknowledge_compliance_policy and compliance_policy_acknowledgements go.
-- The acknowledgements tables, so the policy acknowledgements can move before the module files run.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365)),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists "acknowledgement_assignments_principal_idx" on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
drop policy if exists acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments";
create policy acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists "acknowledgements_user_idx" on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "better_supabase"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
drop policy if exists acknowledgements_read on "better_supabase"."acknowledgements";
create policy acknowledgements_read on "better_supabase"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists "better_supabase"."acknowledgement_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "notified_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
alter table "better_supabase"."acknowledgement_notices" enable row level security;
revoke all on "better_supabase"."acknowledgement_notices" from public, anon, authenticated;
grant all on "better_supabase"."acknowledgement_notices" to service_role;


insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
select x."tenant_id", 'compliance_policy', x."id"::text, 'role', 'member'
from "better_supabase"."policies" x
where x."requires_acknowledgement" and x."archived_at" is null
on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id") do nothing;

do $$
begin
  if to_regclass('"better_supabase".policy_acknowledgements') is null then
    return;
  end if;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "acknowledged_at")
  select x.tenant_id, 'compliance_policy', x.policy_id::text, x.version_id, x.user_id, x.acknowledged_at
  from "better_supabase".policy_acknowledgements x
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
  drop table "better_supabase".policy_acknowledgements cascade;
end;
$$;

drop function if exists "better_supabase"."acknowledge_compliance_policy"(uuid);
drop function if exists "better_supabase"."compliance_policy_acknowledgements"(uuid);
drop function if exists "better_supabase"."list_compliance_policies"(uuid, boolean, boolean);
