-- better-supabase SQL kit: read-sets (0.0.0)
-- One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.

-- Functions for the read sets in `readSets` (better-supabase.config.ts); `gen` and `sql sync` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.

-- config.readSets
-- app_chrome
create or replace function public.rs_app_chrome(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'unread', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."notification_recipients" as t0 where (t0."recipient_user_id" = ((p->>'userId')::uuid) and t0."read_at" is null and t0."dismissed_at" is null))),
    'openTasks', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."tasks" as t0 where (t0."status" = any('{"todo","in_progress"}') and exists (select 1 from "public"."task_assignees" as t1 where t1."task_id" = t0."id" and t1."user_id" = ((p->>'userId')::uuid))))),
    'approvals', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."approval_requests" as t0 where (t0."status" = 'requested' and t0."approver_user_id" = ((p->>'userId')::uuid))))
  )
$rs$;
revoke execute on function public.rs_app_chrome(jsonb) from public, anon, authenticated;
grant execute on function public.rs_app_chrome(jsonb) to authenticated;
