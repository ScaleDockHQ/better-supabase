-- before_ and after_ hooks of the comments, inbox, workflows, enrollments,
-- automations and sequences modules. Each hook is a function in public that
-- raises 'hook:<name>', so a call that throws that message proves the module
-- called it at that point. Acme (…0001) has the admin …a1; supabase/seed.sql
-- has the Help inbox and its one conversation.
begin;
select plan(16);

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

select better_supabase.sync_rule_fields('customer', '[{"id":"name","type":"text"}]');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

-- Fixtures the calls below need.
select better_supabase.save_enrollment_program(
  '00000000-0000-4000-8000-000000000001',
  '{"key":"hook-program","name":"Hook program","subjectTypes":["customer"],"steps":[{"id":"kickoff"}]}'
);
create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids
select 'sequence', (better_supabase.save_sequence('00000000-0000-4000-8000-000000000001',
  '{"key":"hook-seq","name":"Hook seq","status":"active","steps":[{"id":"pause","kind":"wait","minutes":60}]}') ->> 'id')::uuid;
insert into ids
select 'conversation', id from better_supabase.conversations where kind = 'inbox';
insert into ids
select 'comment', (better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer',
  '00000000-0000-4000-8000-00000000a001', 'A comment to assign') ->> 'id')::uuid;
insert into ids
select 'enrollment', (better_supabase.enroll('00000000-0000-4000-8000-000000000001', 'hook-program',
  'customer', '00000000-0000-4000-8000-00000000a001') ->> 'id')::uuid;

-- comments
select pg_temp.set_hook('before_comment_create', 'uuid, text, text, text');
select throws_ok($$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x')$$, 'P0001', 'hook:before_comment_create', 'create_comment calls before_comment_create');
select pg_temp.drop_hook('before_comment_create', 'uuid, text, text, text');
select pg_temp.set_hook('after_comment_create', 'uuid');
select throws_ok($$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x')$$, 'P0001', 'hook:after_comment_create', 'create_comment calls after_comment_create');
select pg_temp.drop_hook('after_comment_create', 'uuid');

select pg_temp.set_hook('before_comment_assign', 'uuid, uuid');
select throws_ok(format($$select better_supabase.assign_comment(%L, '00000000-0000-4000-8000-0000000000a1')$$, (select id from ids where name = 'comment')), 'P0001', 'hook:before_comment_assign', 'assign_comment calls before_comment_assign');
select pg_temp.drop_hook('before_comment_assign', 'uuid, uuid');
select pg_temp.set_hook('after_comment_assign', 'uuid');
select throws_ok(format($$select better_supabase.assign_comment(%L, '00000000-0000-4000-8000-0000000000a1')$$, (select id from ids where name = 'comment')), 'P0001', 'hook:after_comment_assign', 'assign_comment calls after_comment_assign');
select pg_temp.drop_hook('after_comment_assign', 'uuid');

-- enrollments
select pg_temp.set_hook('before_enrollment_create', 'uuid, text, text, text');
select throws_ok($$select better_supabase.enroll('00000000-0000-4000-8000-000000000001', 'hook-program', 'customer', '00000000-0000-4000-8000-00000000a002')$$, 'P0001', 'hook:before_enrollment_create', 'enroll calls before_enrollment_create');
select pg_temp.drop_hook('before_enrollment_create', 'uuid, text, text, text');
select pg_temp.set_hook('after_enrollment_create', 'uuid');
select throws_ok($$select better_supabase.enroll('00000000-0000-4000-8000-000000000001', 'hook-program', 'customer', '00000000-0000-4000-8000-00000000a002')$$, 'P0001', 'hook:after_enrollment_create', 'enroll calls after_enrollment_create');
select pg_temp.drop_hook('after_enrollment_create', 'uuid');
select pg_temp.set_hook('before_enrollment_cancel', 'uuid');
select throws_ok(format($$select better_supabase.cancel_enrollment(%L)$$, (select id from ids where name = 'enrollment')), 'P0001', 'hook:before_enrollment_cancel', 'cancel_enrollment calls before_enrollment_cancel');
select pg_temp.drop_hook('before_enrollment_cancel', 'uuid');
select pg_temp.set_hook('after_enrollment_cancel', 'uuid');
select throws_ok(format($$select better_supabase.cancel_enrollment(%L)$$, (select id from ids where name = 'enrollment')), 'P0001', 'hook:after_enrollment_cancel', 'cancel_enrollment calls after_enrollment_cancel');
select pg_temp.drop_hook('after_enrollment_cancel', 'uuid');

-- sequences
select pg_temp.set_hook('before_sequence_save', 'uuid, jsonb');
select throws_ok($$select better_supabase.save_sequence('00000000-0000-4000-8000-000000000001', '{"key":"other","name":"Other"}')$$, 'P0001', 'hook:before_sequence_save', 'save_sequence calls before_sequence_save');
select pg_temp.drop_hook('before_sequence_save', 'uuid, jsonb');
select pg_temp.set_hook('after_sequence_save', 'uuid');
select throws_ok($$select better_supabase.save_sequence('00000000-0000-4000-8000-000000000001', '{"key":"other","name":"Other"}')$$, 'P0001', 'hook:after_sequence_save', 'save_sequence calls after_sequence_save');
select pg_temp.drop_hook('after_sequence_save', 'uuid');
select pg_temp.set_hook('before_sequence_enroll', 'uuid, text, text');
select throws_ok(format($$select better_supabase.enroll_in_sequence(%L, 'customer', '00000000-0000-4000-8000-00000000a001')$$, (select id from ids where name = 'sequence')), 'P0001', 'hook:before_sequence_enroll', 'enroll_in_sequence calls before_sequence_enroll');
select pg_temp.drop_hook('before_sequence_enroll', 'uuid, text, text');
select pg_temp.set_hook('after_sequence_enroll', 'uuid');
select throws_ok(format($$select better_supabase.enroll_in_sequence(%L, 'customer', '00000000-0000-4000-8000-00000000a001')$$, (select id from ids where name = 'sequence')), 'P0001', 'hook:after_sequence_enroll', 'enroll_in_sequence calls after_sequence_enroll');
select pg_temp.drop_hook('after_sequence_enroll', 'uuid');

-- automations
select pg_temp.set_hook('before_automation_save', 'uuid, jsonb');
select throws_ok($$select better_supabase.save_rule('00000000-0000-4000-8000-000000000001', '{"subjectType":"customer","trigger":"customer.updated","name":"Hook rule"}')$$, 'P0001', 'hook:before_automation_save', 'save_rule calls before_automation_save');
select pg_temp.drop_hook('before_automation_save', 'uuid, jsonb');
select pg_temp.set_hook('after_automation_save', 'uuid');
select throws_ok($$select better_supabase.save_rule('00000000-0000-4000-8000-000000000001', '{"subjectType":"customer","trigger":"customer.updated","name":"Hook rule"}')$$, 'P0001', 'hook:after_automation_save', 'save_rule calls after_automation_save');
select pg_temp.drop_hook('after_automation_save', 'uuid');
insert into ids
select 'rule', (better_supabase.save_rule('00000000-0000-4000-8000-000000000001', '{"subjectType":"customer","trigger":"customer.updated","name":"Remove me"}') ->> 'id')::uuid;
select pg_temp.set_hook('before_automation_remove', 'uuid');
select throws_ok(format($$select better_supabase.remove_rule(%L)$$, (select id from ids where name = 'rule')), 'P0001', 'hook:before_automation_remove', 'remove_rule calls before_automation_remove');
select pg_temp.drop_hook('before_automation_remove', 'uuid');
select pg_temp.set_hook('after_automation_remove', 'uuid');
select throws_ok(format($$select better_supabase.remove_rule(%L)$$, (select id from ids where name = 'rule')), 'P0001', 'hook:after_automation_remove', 'remove_rule calls after_automation_remove');
select pg_temp.drop_hook('after_automation_remove', 'uuid');

select * from finish();
rollback;
