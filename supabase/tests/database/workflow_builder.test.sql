-- The workflow-builder module against the seed: an Acme admin (…a1) edits
-- and publishes, an Acme member (…a2) only reads, and webhook token hashes
-- stay with the service role. Run with `supabase test db`.
begin;
select plan(9);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase' and tablename like 'workflow\_%' and not rowsecurity),
  0::bigint,
  'every workflow table in better_supabase has RLS enabled'
);
select table_privs_are('better_supabase', 'workflow_webhook_tokens', 'authenticated', '{}'::text[],
  'authenticated cannot touch webhook token hashes');
select function_privs_are('better_supabase', 'workflow_webhook_target', array['text'], 'authenticated', '{}'::text[],
  'only the service role resolves a webhook token');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.sync_workflow_steps('{}'::jsonb)$$,
  '42501',
  null,
  'only the service role writes the step library'
);
select isnt(
  (better_supabase.save_workflow_definition('00000000-0000-4000-8000-000000000001', 'welcome', 'Welcome') ->> 'id'),
  null,
  'an admin creates a definition'
);
select is(
  (better_supabase.publish_workflow_version(
    (better_supabase.save_workflow_draft(
      (select id from better_supabase.workflow_definitions where slug = 'welcome'),
      '{"nodes":[{"id":"t","kind":"trigger"}],"edges":[]}'::jsonb
    ) ->> 'id')::uuid
  ) ->> 'status'),
  'published',
  'an admin publishes a valid graph'
);
select throws_ok(
  $$select better_supabase.publish_workflow_version((better_supabase.save_workflow_draft(
    (select id from better_supabase.workflow_definitions where slug = 'welcome'),
    '{"nodes":[{"id":"t","kind":"trigger"},{"id":"s","kind":"step","step":"missing"}],"edges":[{"id":"e","source":"t","target":"s"}]}'::jsonb
  ) ->> 'id')::uuid)$$,
  '22023',
  null,
  'publishing a graph with a step outside the library fails'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.workflow_definitions where slug = 'welcome'),
  1::bigint,
  'a member reads the tenant''s definitions'
);
select throws_ok(
  $$select better_supabase.save_workflow_definition('00000000-0000-4000-8000-000000000001', 'mine', 'Mine')$$,
  '42501',
  null,
  'a member cannot create a definition'
);

select * from finish();
rollback;
