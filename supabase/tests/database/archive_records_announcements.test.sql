-- Archive, restore and purge for announcements (ADR 1042). An archived
-- announcement leaves the active list and the staff list, keeps its row and
-- dismissals, and `purge_announcement` replaces `delete_announcement`. Run with
-- `supabase test db`.
begin;
select plan(12);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select set_config('test.announcement', (better_supabase.upsert_announcement(
  null, '{"title": "Maintenance tonight"}'::jsonb
) ->> 'id'), true);

select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.active_announcements())
    where value ->> 'id' = current_setting('test.announcement')),
  1,
  'a new announcement is active'
);

select isnt(
  better_supabase.archive_announcement(current_setting('test.announcement')::uuid) ->> 'archived_at',
  null,
  'archive sets archived_at'
);
select is(pg_temp.n('announcement.archived'), 1, 'archive records announcement.archived once');
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.active_announcements())
    where value ->> 'id' = current_setting('test.announcement')),
  0,
  'an archived announcement is not active'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_announcements())
    where value ->> 'id' = current_setting('test.announcement')),
  0,
  'the staff list hides an archived announcement'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_announcements(true))
    where value ->> 'id' = current_setting('test.announcement')),
  1,
  'include_archived lists it'
);

select better_supabase.archive_announcement(current_setting('test.announcement')::uuid);
select is(pg_temp.n('announcement.archived'), 1, 'archiving twice records nothing more');

select is(
  better_supabase.restore_announcement(current_setting('test.announcement')::uuid) ->> 'archived_at',
  null,
  'restore clears archived_at'
);
select is(pg_temp.n('announcement.restored'), 1, 'restore records announcement.restored once');

select is(
  better_supabase.purge_announcement(current_setting('test.announcement')::uuid),
  true,
  'purge removes the row'
);
select is(pg_temp.n('announcement.purged'), 1, 'purge records announcement.purged');
select hasnt_function(
  'better_supabase',
  'delete_announcement',
  array['uuid'],
  'delete_announcement is gone'
);

select * from finish();
rollback;
