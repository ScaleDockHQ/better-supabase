create view "public"."projects_view" with (security_invoker = true) as
select t."id",
  t."organization_id",
  t."created_at",
  t."updated_at",
  t."name",
  t."budget_minor",
  t."currency",
  t."lead_id",
  t."label_id",
  t."deleted_at",
  r0.value as "open_tasks",
  r1.value as "done_tasks",
  r2.value as "next_due_on"
from "public"."projects" t
  left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id and c."status" = 'todo') r0 on true
  left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id and c."status" = 'done') r1 on true
  left join lateral (select min(c."due_on") as value from "public"."tasks" c where c."project_id" = t.id) r2 on true;

revoke all on "public"."projects_view" from public, anon, authenticated;

grant select on "public"."projects_view" to authenticated;

grant select on "public"."projects_view" to service_role;

comment on view "public"."projects_view" is 'The rollups and lookups of public.projects, read with the caller''s row level security.';
