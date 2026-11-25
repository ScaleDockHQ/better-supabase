-- An event's xid orders the outbox and decides when it is settled, so it is
-- always the writing transaction's id: an app that lets clients insert events
-- can't plant one that sorts past every consumer's cursor or never settles.
begin;
select plan(2);

insert into better_supabase.outbox_events (type, payload, xid)
values ('test.planted', '{}', '999999999999'::xid8);
select is(
  (select xid from better_supabase.outbox_events where type = 'test.planted'),
  pg_current_xact_id(),
  'an insert gets the transaction''s own xid, whatever it names'
);

update better_supabase.outbox_events set xid = '1'::xid8 where type = 'test.planted';
select is(
  (select xid from better_supabase.outbox_events where type = 'test.planted'),
  pg_current_xact_id(),
  'an update keeps the xid'
);

select * from finish();
rollback;
