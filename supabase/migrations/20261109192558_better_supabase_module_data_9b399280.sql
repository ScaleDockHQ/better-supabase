-- better-supabase add --adopt: the rows and settings of teams that no data migration holds yet.

set lock_timeout = '5s';

-- teams
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
