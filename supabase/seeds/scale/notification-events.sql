-- One batch of the scale seed: notification events {{from}} to {{to}} of {{total}} in the Acme
-- organization, each with a recipient. 20% go to admin@acme.test, the rest to
-- the other members, and about 3% are unread.
with e as (
  insert into better_supabase.notification_events (id, tenant_id, type, summary, created_at)
  select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'scale.type_' || (g % 8),
         'Scale notification ' || g, now() - (g::numeric / {{total}} * interval '60 days')
  from generate_series({{from}}, {{to}}) g
  returning id, tenant_id, created_at
)
insert into better_supabase.notification_recipients (event_id, tenant_id, user_id, read_at, created_at)
select id, tenant_id,
  case (abs(hashtext(id::text)) % 5) when 0 then '00000000-0000-4000-8000-0000000000a1'::uuid
       when 1 then '00000000-0000-4000-8000-0000000000a2'::uuid
       when 2 then '00000000-0000-4000-8000-0000000000a3'::uuid
       when 3 then '00000000-0000-4000-8000-0000000000a2'::uuid
       else '00000000-0000-4000-8000-0000000000a3'::uuid end,
  case when abs(hashtext(id::text)) % 33 = 0 then null else created_at end,
  created_at
from e
