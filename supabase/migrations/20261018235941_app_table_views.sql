CREATE VIEW "public"."projects_view" WITH (security_invoker=true) AS  SELECT t.id,
    t.organization_id,
    t.created_at,
    t.updated_at,
    t.name,
    t.budget_minor,
    t.currency,
    t.lead_id,
    t.label_id,
    t.deleted_at,
    r0.value AS open_tasks,
    r1.value AS done_tasks,
    r2.value AS next_due_on
   FROM (((public.projects t
     LEFT JOIN LATERAL ( SELECT count(*) AS value
           FROM public.tasks c
          WHERE ((c.project_id = t.id) AND (c.status = 'todo'::text))) r0 ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS value
           FROM public.tasks c
          WHERE ((c.project_id = t.id) AND (c.status = 'done'::text))) r1 ON (true))
     LEFT JOIN LATERAL ( SELECT min(c.due_on) AS value
           FROM public.tasks c
          WHERE (c.project_id = t.id)) r2 ON (true));

REVOKE ALL ON TABLE "public"."projects_view" FROM "anon";

CREATE VIEW "public"."tasks_view" WITH (security_invoker=true) AS  SELECT t.id,
    t.organization_id,
    t.created_at,
    t.updated_at,
    t.title,
    t.status,
    t.starts_on,
    t.due_on,
    t.assignee_id,
    t.project_id,
    t.rank,
    l0.value AS project_name
   FROM (public.tasks t
     LEFT JOIN LATERAL ( SELECT r.name AS value
           FROM public.projects r
          WHERE (r.id = t.project_id)) l0 ON (true));

REVOKE ALL ON TABLE "public"."tasks_view" FROM "anon";

COMMENT ON VIEW "public"."projects_view" IS 'The rollups and lookups of public.projects, read with the caller''s row level security.';

COMMENT ON VIEW "public"."tasks_view" IS 'The rollups and lookups of public.tasks, read with the caller''s row level security.';

REVOKE ALL ON TABLE "public"."projects_view" FROM "authenticated";

GRANT SELECT ON TABLE "public"."projects_view" TO "authenticated";

REVOKE ALL ON TABLE "public"."projects_view" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."projects_view" TO "postgres";

REVOKE ALL ON TABLE "public"."projects_view" FROM "service_role";

GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE "public"."projects_view" TO "service_role";

REVOKE ALL ON TABLE "public"."tasks_view" FROM "authenticated";

GRANT SELECT ON TABLE "public"."tasks_view" TO "authenticated";

REVOKE ALL ON TABLE "public"."tasks_view" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tasks_view" TO "postgres";

REVOKE ALL ON TABLE "public"."tasks_view" FROM "service_role";

GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE "public"."tasks_view" TO "service_role";
