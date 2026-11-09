-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:ff981401d94c27fe6386e03fa31cc832ac665881730d130366b9fa95ff33f7ea
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Members with an employee record get its id.
update "better_supabase"."team_members" y set "employee_id" = x."id"
from "better_supabase"."employees" x
where y."employee_id" is null and x."tenant_id" = y."tenant_id" and x."user_id" = y."user_id"
  and not exists (
    select 1 from "better_supabase"."team_members" z
    where z."team_id" = y."team_id" and z."employee_id" = x."id"
  );
insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
select t."id",
  case when exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = x."tenant_id"
      and m."user_id" = x."user_id"
  ) then x."user_id" end,
  x."id", x."tenant_id"
from "better_supabase"."employees" x
join "better_supabase"."teams" t on t."id" = x."team_id" and t."tenant_id" = x."tenant_id"
on conflict do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
