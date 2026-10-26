create view "public"."tasks_view" with (security_invoker = true) as
select t.*,
  l0.value as "project_name"
from "public"."tasks" t
  left join lateral (select r."name" as value from "public"."projects" r where r.id = t."project_id") l0 on true;

revoke all on "public"."tasks_view" from public, anon, authenticated;

grant select on "public"."tasks_view" to authenticated;

grant select on "public"."tasks_view" to service_role;

comment on view "public"."tasks_view" is 'The rollups and lookups of public.tasks, read with the caller''s row level security.';
