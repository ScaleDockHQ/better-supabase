-- Staff order states (ADR 0665). The Acme admin (…a1) saves a draft order from
-- lines: it holds no stock and records order.drafted, not order.placed.
-- Confirming it makes a confirmed order and records order.placed once. A
-- confirmed order goes on hold and comes back to the status it was held from;
-- a held or draft order can be cancelled; a member (…a2) can't hold or
-- confirm. Run with `supabase test db`.
begin;
select plan(17);

-- The outbox is readable by the service role only; this reads it for the tests.
create function pg_temp.events(p_type text, p_order text) returns integer
language sql security definer as $$
  select count(*)::int from better_supabase.outbox_events where type = p_type and subject = 'orders/' || p_order
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Setup service', 'setup-service-draft', null, 'service', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'SETUP-DRAFT', null, 'Setup', null, null, false, false, null) ->> 'id', true);

select set_config('t.draft', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 2, 'unitAmount', '2500')),
  jsonb_build_object('currency', 'EUR', 'draft', true, 'origin', jsonb_build_object('type', 'phone', 'id', 'draft-1')))::text, true);

select is(
  current_setting('t.draft')::jsonb ->> 'status',
  'draft',
  'draft: true saves the order as a draft'
);
select is(
  pg_temp.events('order.drafted', current_setting('t.draft')::jsonb ->> 'id'),
  1,
  'a draft records order.drafted'
);
select is(
  pg_temp.events('order.placed', current_setting('t.draft')::jsonb ->> 'id'),
  0,
  'a draft does not record order.placed'
);
select is(
  better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
    jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 2, 'unitAmount', '2500')),
    jsonb_build_object('currency', 'EUR', 'draft', true, 'origin', jsonb_build_object('type', 'phone', 'id', 'draft-1'))) ->> 'created',
  'false',
  'a draft claims its origin once'
);
select throws_ok(
  format($$select better_supabase.hold_order(%L, 'too early')$$, current_setting('t.draft')::jsonb ->> 'id'),
  '55000',
  'only an order waiting for payment or a confirmed one can be put on hold',
  'a draft can''t be put on hold'
);

select set_config('t.order', better_supabase.confirm_draft_order((current_setting('t.draft')::jsonb ->> 'id')::uuid)::text, true);
select is(
  current_setting('t.order')::jsonb ->> 'status',
  'confirmed',
  'confirm_draft_order makes a confirmed order'
);
select is(
  pg_temp.events('order.placed', current_setting('t.draft')::jsonb ->> 'id'),
  1,
  'confirming records order.placed'
);
select throws_ok(
  format($$select better_supabase.confirm_draft_order(%L)$$, current_setting('t.draft')::jsonb ->> 'id'),
  '55000',
  'only a draft order can be confirmed',
  'a confirmed order can''t be confirmed again'
);

select is(
  better_supabase.hold_order((current_setting('t.draft')::jsonb ->> 'id')::uuid, 'Credit check') ->> 'status',
  'on_hold',
  'hold_order puts a confirmed order on hold'
);
select is(
  (select jsonb_build_array(held_from, hold_reason, held_at is not null) from better_supabase.orders where id = (current_setting('t.draft')::jsonb ->> 'id')::uuid),
  '["confirmed", "Credit check", true]'::jsonb,
  'the order remembers where it was held from and why'
);
select throws_ok(
  format($$select better_supabase.create_fulfillment(%L)$$, current_setting('t.draft')::jsonb ->> 'id'),
  '55000',
  'only a paid or confirmed order can be fulfilled',
  'a held order can''t be fulfilled'
);
select is(
  better_supabase.release_order_hold((current_setting('t.draft')::jsonb ->> 'id')::uuid) ->> 'status',
  'confirmed',
  'release_order_hold returns the order to the status it was held from'
);
select is(
  (select jsonb_build_array(held_from, hold_reason, held_at) from better_supabase.orders where id = (current_setting('t.draft')::jsonb ->> 'id')::uuid),
  '[null, null, null]'::jsonb,
  'releasing clears the hold columns'
);
select diag(pg_temp.events('order.hold_placed', current_setting('t.draft')::jsonb ->> 'id')::text, pg_temp.events('order.hold_released', current_setting('t.draft')::jsonb ->> 'id')::text);
select is(
  pg_temp.events('order.hold_placed', current_setting('t.draft')::jsonb ->> 'id') + pg_temp.events('order.hold_released', current_setting('t.draft')::jsonb ->> 'id'),
  2,
  'a hold and its release each record an event'
);

-- A held order can be cancelled.
select better_supabase.hold_order((current_setting('t.draft')::jsonb ->> 'id')::uuid, null);
select is(
  better_supabase.cancel_order((current_setting('t.draft')::jsonb ->> 'id')::uuid, 'customer left'),
  true,
  'an order on hold can be cancelled'
);

-- A draft that was never confirmed can be cancelled too.
select set_config('t.second', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 1, 'unitAmount', '900')),
  jsonb_build_object('currency', 'EUR', 'draft', true))::text, true);
select is(
  better_supabase.cancel_order((current_setting('t.second')::jsonb ->> 'id')::uuid, null),
  true,
  'a draft can be cancelled'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.hold_order(%L, null)$$, current_setting('t.draft')::jsonb ->> 'id'),
  '42501',
  null,
  'a member can''t hold an order'
);

select * from finish();
rollback;
