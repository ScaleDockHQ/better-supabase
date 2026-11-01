-- before_ and after_ hooks of the inbox and workflows modules; the method is
-- the one in module_hooks.test.sql. Workflow writes run as the service role.
begin;
select plan(12);

create function pg_temp.set_hook(p_name text, p_args text) returns void
language plpgsql as $f$
begin
  execute format(
    'create function public.%I(%s) returns void language plpgsql as $b$ begin raise exception %L using errcode = ''P0001''; end $b$',
    p_name, p_args, 'hook:' || p_name
  );
end;
$f$;
create function pg_temp.drop_hook(p_name text, p_args text) returns void
language plpgsql as $f$
begin
  execute format('drop function public.%I(%s)', p_name, p_args);
end;
$f$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids
select 'conversation', id from better_supabase.conversations where kind = 'inbox';

-- inbox
select pg_temp.set_hook('before_inbox_conversation_start', 'uuid, jsonb');
select throws_ok($$select better_supabase.start_conversation('00000000-0000-4000-8000-00000000e001', '{"subject":"Hello","body":"Hi"}')$$, 'P0001', 'hook:before_inbox_conversation_start', 'start_conversation calls before_inbox_conversation_start');
select pg_temp.drop_hook('before_inbox_conversation_start', 'uuid, jsonb');
select pg_temp.set_hook('after_inbox_conversation_start', 'uuid');
select throws_ok($$select better_supabase.start_conversation('00000000-0000-4000-8000-00000000e001', '{"subject":"Hello","body":"Hi"}')$$, 'P0001', 'hook:after_inbox_conversation_start', 'start_conversation calls after_inbox_conversation_start');
select pg_temp.drop_hook('after_inbox_conversation_start', 'uuid');

select pg_temp.set_hook('before_inbox_message_send', 'uuid, jsonb');
select throws_ok(format($$select better_supabase.send_inbox_message(%L, '{"kind":"note","body":"x"}')$$, (select id from ids where name = 'conversation')), 'P0001', 'hook:before_inbox_message_send', 'send_inbox_message calls before_inbox_message_send');
select pg_temp.drop_hook('before_inbox_message_send', 'uuid, jsonb');
select pg_temp.set_hook('after_inbox_message_send', 'uuid');
select throws_ok(format($$select better_supabase.send_inbox_message(%L, '{"kind":"note","body":"x"}')$$, (select id from ids where name = 'conversation')), 'P0001', 'hook:after_inbox_message_send', 'send_inbox_message calls after_inbox_message_send');
select pg_temp.drop_hook('after_inbox_message_send', 'uuid');

select pg_temp.set_hook('before_inbox_conversation_assign', 'uuid, uuid, uuid');
select throws_ok(format($$select better_supabase.assign_conversation(%L, '00000000-0000-4000-8000-0000000000a1')$$, (select id from ids where name = 'conversation')), 'P0001', 'hook:before_inbox_conversation_assign', 'assign_conversation calls before_inbox_conversation_assign');
select pg_temp.drop_hook('before_inbox_conversation_assign', 'uuid, uuid, uuid');
select pg_temp.set_hook('after_inbox_conversation_assign', 'uuid');
select throws_ok(format($$select better_supabase.assign_conversation(%L, '00000000-0000-4000-8000-0000000000a1')$$, (select id from ids where name = 'conversation')), 'P0001', 'hook:after_inbox_conversation_assign', 'assign_conversation calls after_inbox_conversation_assign');
select pg_temp.drop_hook('after_inbox_conversation_assign', 'uuid');

select pg_temp.set_hook('before_inbox_conversation_status_change', 'uuid, text');
select throws_ok(format($$select better_supabase.set_conversation_status(%L, 'resolved')$$, (select id from ids where name = 'conversation')), 'P0001', 'hook:before_inbox_conversation_status_change', 'set_conversation_status calls before_inbox_conversation_status_change');
select pg_temp.drop_hook('before_inbox_conversation_status_change', 'uuid, text');
select pg_temp.set_hook('after_inbox_conversation_status_change', 'uuid');
select throws_ok(format($$select better_supabase.set_conversation_status(%L, 'resolved')$$, (select id from ids where name = 'conversation')), 'P0001', 'hook:after_inbox_conversation_status_change', 'set_conversation_status calls after_inbox_conversation_status_change');
select pg_temp.drop_hook('after_inbox_conversation_status_change', 'uuid');

-- workflows
select pg_temp.set_hook('before_workflow_schedule_create', 'text, text, uuid');
select throws_ok($$select better_supabase.create_workflow_schedule('nightly', 'nightly-job', '0 3 * * *', now() + interval '1 day', '{}', 'UTC', '00000000-0000-4000-8000-000000000001')$$, 'P0001', 'hook:before_workflow_schedule_create', 'create_workflow_schedule calls before_workflow_schedule_create');
select pg_temp.drop_hook('before_workflow_schedule_create', 'text, text, uuid');
select pg_temp.set_hook('after_workflow_schedule_create', 'uuid');
select throws_ok($$select better_supabase.create_workflow_schedule('nightly', 'nightly-job', '0 3 * * *', now() + interval '1 day', '{}', 'UTC', '00000000-0000-4000-8000-000000000001')$$, 'P0001', 'hook:after_workflow_schedule_create', 'create_workflow_schedule calls after_workflow_schedule_create');
select pg_temp.drop_hook('after_workflow_schedule_create', 'uuid');
select pg_temp.set_hook('before_workflow_start_request', 'text, text, uuid');
select throws_ok($$select better_supabase.request_workflow_start('hook-key', 'nightly-job', '{}', '00000000-0000-4000-8000-000000000001')$$, 'P0001', 'hook:before_workflow_start_request', 'request_workflow_start calls before_workflow_start_request');
select pg_temp.drop_hook('before_workflow_start_request', 'text, text, uuid');
select pg_temp.set_hook('after_workflow_start_request', 'uuid');
select throws_ok($$select better_supabase.request_workflow_start('hook-key', 'nightly-job', '{}', '00000000-0000-4000-8000-000000000001')$$, 'P0001', 'hook:after_workflow_start_request', 'request_workflow_start calls after_workflow_start_request');
select pg_temp.drop_hook('after_workflow_start_request', 'uuid');

select * from finish();
rollback;
