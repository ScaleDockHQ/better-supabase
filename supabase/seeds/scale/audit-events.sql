-- One batch of the scale seed: audit events numbered {{from}} to {{to}} of {{total}}. About 80%
-- belong to the Acme organization, spread over 24 months, with the members of the
-- organization as actors and about 40 event types.
insert into better_supabase.audit_events (
  table_name, record_id, op, changed, actor_id, actor_role, tenant_id, occurred_at,
  event_type, category, outcome, source, target_type, actor_kind, actor_label,
  tenant_label, target_label, summary
)
select
  'tasks', md5(g::text), 'event', null,
  case g % 3 when 0 then '00000000-0000-4000-8000-0000000000a1'::uuid
             when 1 then '00000000-0000-4000-8000-0000000000a2'::uuid
             else '00000000-0000-4000-8000-0000000000a3'::uuid end,
  'authenticated',
  case when g % 5 = 0 then '00000000-0000-4000-8000-000000000002'::uuid
       else '00000000-0000-4000-8000-000000000001'::uuid end,
  now() - (g::numeric / {{total}} * interval '730 days'),
  'scale.event_' || (g % 40), 'data', case when g % 50 = 0 then 'failure' else 'success' end,
  'app', 'task', 'user', 'Member ' || (g % 3), 'Acme', 'Task ' || (g % 1000),
  'Member ' || (g % 3) || ' changed task ' || (g % 1000)
from generate_series({{from}}, {{to}}) g
