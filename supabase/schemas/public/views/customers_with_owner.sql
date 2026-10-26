create view "public"."customers_with_owner" with (security_invoker = true) as
select c."id",
  c."organization_id",
  c."name",
  c."status",
  c."owner_team_id",
  t."name" as "owner_team_name"
from "public"."customers" c
  left join "better_supabase"."teams" t
    on t."id" = c."owner_team_id" and t."tenant_id" = c."organization_id"
where c."archived_at" is null;

revoke all on "public"."customers_with_owner" from public, anon, authenticated;

grant select on "public"."customers_with_owner" to authenticated;

grant select on "public"."customers_with_owner" to service_role;

comment on view "public"."customers_with_owner" is 'Open customers with the name of the team that owns them, read with the caller''s row level security on both tables.';
