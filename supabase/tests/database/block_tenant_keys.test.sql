-- Block tables keep a row and the row it references in one tenant: teams and
-- other block tables have a unique (tenant_id, id) key, and team_members
-- references its team with the tenant. The import issue helpers are internal.
begin;
select plan(7);

insert into better_supabase.teams (id, tenant_id, name, slug)
values ('00000000-0000-4000-8000-0000000000f7', '00000000-0000-4000-8000-000000000002', 'Globex ops', 'globex-ops');

select throws_ok(
  $$insert into better_supabase.team_members (team_id, user_id, tenant_id)
    values ('00000000-0000-4000-8000-0000000000f7', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000001')$$,
  '23503',
  null,
  'a member row cannot point at another tenant''s team'
);

select ok(
  exists (
    select 1 from pg_index i
    join pg_class c on c.oid = i.indexrelid
    where c.relname = 'bsb_teams_tenant_id_key' and i.indisunique
  ),
  'teams has a unique (tenant_id, id) key'
);

select is(
  (
    select count(*)::int from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_index i on i.indexrelid = c.oid
    where n.nspname = 'better_supabase' and i.indisunique
      and c.relname in (
        'bsb_companies_tenant_id_key', 'bsb_people_tenant_id_key',
        'bsb_party_locations_tenant_id_key', 'bsb_attachments_tenant_id_key',
        'bsb_ledger_transactions_tenant_id_key'
      )
  ),
  5,
  'contacts, attachments and ledger tables have a unique (tenant_id, id) key'
);

select ok(
  not has_function_privilege('authenticated', 'better_supabase.import_clear_issues(uuid, text, text)', 'execute'),
  'authenticated cannot call import_clear_issues'
);
select ok(
  not has_function_privilege('anon', 'better_supabase.import_note_issue(uuid, text, text, text, text, text)', 'execute'),
  'anon cannot call import_note_issue'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.import_note_warnings(uuid, text, jsonb)', 'execute'),
  'authenticated cannot call import_note_warnings'
);

select lives_ok(
  $$insert into better_supabase.team_members (team_id, user_id, tenant_id)
    select '00000000-0000-4000-8000-0000000000f7', m.user_id, m.organization_id
    from public.memberships m
    where m.organization_id = '00000000-0000-4000-8000-000000000002'
    limit 1$$,
  'a member row in the team''s own tenant is accepted'
);

select * from finish();
rollback;
