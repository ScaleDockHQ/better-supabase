-- Comment reads for a member of many tenants (ADR 0675): bsb.scale_tenants
-- tenants (default 50) with three projects each, every project with a record
-- conversation and one comment, so the caller reads about 150 record
-- conversations. list_comments on one record, messaging_messages_json over a
-- 50-comment thread and comment_counts over one tenant's records print
-- SCALE_MS; they check each conversation once and read its messages by key,
-- so none grows with the other conversations or with the thread's length.
-- A user outside the tenants reads nothing, and the inlined policy sees the
-- same conversations as can_subject per row. SCALE_CALLS counts the
-- can_subject calls of each read.
begin;
select plan(13);

select set_config('bsb.tenants', coalesce(nullif(current_setting('bsb.scale_tenants', true), ''), '50'), true);

set local track_functions = 'all';
set local session_replication_role = replica;

create temp table scale_orgs as
select gen_random_uuid() as id, g from generate_series(1, current_setting('bsb.tenants')::int) g;

insert into public.organizations (id, name, slug)
select id, 'Scale comments ' || g, 'scale-comments-' || g from scale_orgs;

insert into public.memberships (organization_id, user_id, role)
select o.id, '00000000-0000-4000-8000-0000000000a1', r.id
from scale_orgs o join better_supabase.roles r on r.key = 'member';

create temp table scale_projects as
select gen_random_uuid() as id, o.id as org, o.g, p from scale_orgs o, generate_series(1, 3) p;

insert into public.projects (id, organization_id, name)
select id, org, 'Scale project ' || g || '.' || p from scale_projects;

insert into better_supabase.conversations (id, tenant_id, kind, access, subject_type, subject_id)
select id, org, 'subject', 'subject', 'project', id::text from scale_projects;

insert into better_supabase.messages (tenant_id, conversation_id, author_id, body, sent_at)
select org, id, '00000000-0000-4000-8000-0000000000a1', 'Scale comment', now() from scale_projects;

insert into better_supabase.messages (tenant_id, conversation_id, author_id, body, sent_at)
select org, id, '00000000-0000-4000-8000-0000000000a1', 'Thread comment ' || n, now() + (n || ' seconds')::interval
from scale_projects, generate_series(1, 49) n
where g = 1 and p = 2;

set local session_replication_role = origin;

analyze better_supabase.conversations;
analyze better_supabase.messages;
analyze public.projects;

select org as tenant, id as one from scale_projects where g = 1 and p = 1 \gset
select id as thread from scale_projects where g = 1 and p = 2 \gset
select array_agg(id::text)::text as ids from scale_projects where org = :'tenant' \gset

grant select on scale_projects to public;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t, 0::bigint as calls;
grant all on t0 to public;

create function pg_temp.can_subject_calls() returns bigint language sql as
$$ select coalesce(pg_stat_get_xact_function_calls('better_supabase.can_subject(text,text,text)'::regprocedure), 0) $$;

select better_supabase.list_comments(:'tenant', 'project', :'one') is not null as warm \gset
update t0 set t = clock_timestamp(), calls = pg_temp.can_subject_calls();

select jsonb_array_length(better_supabase.list_comments(:'tenant', 'project', :'one')) as one_count \gset
select pg_temp.can_subject_calls() - (select calls from t0) as one_calls \gset
select diag('SCALE_MS list_comments_one=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000) || ' SCALE_CALLS ' || (pg_temp.can_subject_calls() - (select calls from t0)));
update t0 set calls = pg_temp.can_subject_calls();

update t0 set t = clock_timestamp(), calls = pg_temp.can_subject_calls();
select jsonb_array_length(better_supabase.list_comments(:'tenant', 'project', :'thread')) as thread_count \gset
select pg_temp.can_subject_calls() - (select calls from t0) as thread_calls \gset
select diag('SCALE_MS list_comments_thread_50=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000) || ' SCALE_CALLS ' || (pg_temp.can_subject_calls() - (select calls from t0)));
update t0 set calls = pg_temp.can_subject_calls();

update t0 set t = clock_timestamp(), calls = pg_temp.can_subject_calls();
select jsonb_array_length(better_supabase.messaging_messages_json(array(
  select m.id from better_supabase.messages m where m.conversation_id = :'thread'
))) as json_count \gset
select pg_temp.can_subject_calls() - (select calls from t0) as json_calls \gset
select diag('SCALE_MS messages_json_thread_50=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000) || ' SCALE_CALLS ' || (pg_temp.can_subject_calls() - (select calls from t0)));
update t0 set calls = pg_temp.can_subject_calls();

update t0 set t = clock_timestamp(), calls = pg_temp.can_subject_calls();
select better_supabase.comment_counts(:'tenant', 'project', :'ids'::text[]) as counts \gset
select pg_temp.can_subject_calls() - (select calls from t0) as counts_calls \gset
select diag('SCALE_MS comment_counts_tenant=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000) || ' SCALE_CALLS ' || (pg_temp.can_subject_calls() - (select calls from t0)));
update t0 set calls = pg_temp.can_subject_calls();

update t0 set t = clock_timestamp(), calls = pg_temp.can_subject_calls();
select count(*) as by_policy from better_supabase.conversations c
where c.id in (select id from scale_projects) \gset
select diag('SCALE_MS conversations_policy=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select count(*) as by_function from better_supabase.conversations c
where c.id in (select id from scale_projects)
  and coalesce(better_supabase.can_subject(c.subject_type, c.subject_id, 'read'), false) \gset

select is(:one_count, 1, 'a member reads the one comment on a record');
select cmp_ok(:one_calls::bigint, '<', 10::bigint, 'reading one comment checks its own conversation, not every conversation the member reads');
select is(:thread_count, 50, 'a member reads every comment of a thread');
select cmp_ok(:thread_calls::bigint, '<', 10::bigint, 'reading a 50-comment thread checks its conversation a fixed number of times');
select is(:json_count, 50, 'messaging_messages_json returns every message of the thread');
select cmp_ok(:json_calls::bigint, '<', 6::bigint, 'messaging_messages_json checks the one conversation of 50 ids a fixed number of times');
select is(:'counts'::jsonb ->> :'thread', '50', 'comment_counts counts the thread');
select cmp_ok(:counts_calls::bigint, '<=', 8::bigint, 'comment_counts checks each of the tenant''s three conversations, not every message');
select is(:by_policy::bigint, current_setting('bsb.tenants')::bigint * 3, 'the member reads every record conversation');
select is(:by_function::bigint, :by_policy::bigint, 'can_subject per row sees the same conversations');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
set local role authenticated;

select is(better_supabase.list_comments(:'tenant', 'project', :'one'), '[]'::jsonb, 'a user outside the tenant reads no comments');
select is(better_supabase.comment_counts(:'tenant', 'project', :'ids'::text[]), '{}'::jsonb, 'a user outside the tenant counts no comments');
select is((select count(*) from better_supabase.conversations c where c.id in (select id from scale_projects)), 0::bigint, 'a user outside the tenants reads no record conversation');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
