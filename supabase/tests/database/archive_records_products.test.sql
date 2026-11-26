-- Archive, restore and purge for products and variants (ADR 1048 and 1049).
-- Archive and restore use the product's status, so each records its own event
-- next to the status change. A channel lists an archived product only on
-- request. The example maps no variant status, so archiving a variant refuses.
-- Run with `supabase test db`.
begin;
select plan(15);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select set_config('t.p', better_supabase.upsert_product('00000000-0000-4000-8000-000000000001', null, 'Shirt', 'shirt-y2g', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.upsert_variant(current_setting('t.p')::uuid, null, 'SHIRT-Y2G', null, 'Shirt', null, null, true, false, null) ->> 'id', true);
select better_supabase.set_product_status(current_setting('t.p')::uuid, 'active');
select set_config('t.c', better_supabase.upsert_catalog_channel('00000000-0000-4000-8000-000000000001', null, 'web-y2g', 'Web', 'EUR', null, true) ->> 'id', true);
select better_supabase.set_channel_listing(current_setting('t.c')::uuid, array[current_setting('t.p')::uuid], true);

select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.channel_products(current_setting('t.c')::uuid))
   where value ->> 'id' = current_setting('t.p')),
  1, 'an active listed product is in the channel'
);

select is(better_supabase.archive_product(current_setting('t.p')::uuid) ->> 'status', 'archived', 'archive sets the archived status');
select is(pg_temp.n('product.archived'), 1, 'archive records product.archived once');
select better_supabase.archive_product(current_setting('t.p')::uuid);
select is(pg_temp.n('product.archived'), 1, 'archiving twice records nothing more');

select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.channel_products(current_setting('t.c')::uuid))
   where value ->> 'id' = current_setting('t.p')),
  0, 'the channel hides an archived product'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.channel_products(current_setting('t.c')::uuid, archived => true))
   where value ->> 'id' = current_setting('t.p')),
  1, 'the archived filter lists it'
);

select is(better_supabase.restore_product(current_setting('t.p')::uuid) ->> 'status', 'draft', 'restore puts the product back to draft');
select is(pg_temp.n('product.restored'), 1, 'restore records product.restored once');
select better_supabase.restore_product(current_setting('t.p')::uuid);
select is(pg_temp.n('product.restored'), 1, 'restoring a product that is not archived records nothing');

select throws_ok(
  format($$select better_supabase.archive_variant(%L)$$, current_setting('t.v')),
  '22023', null, 'a variants table without a status refuses to archive'
);
select throws_ok(
  format($$select better_supabase.restore_variant(%L)$$, current_setting('t.v')),
  '22023', null, 'and refuses to restore'
);

select is(better_supabase.purge_variant(current_setting('t.v')::uuid), true, 'purge deletes a variant');
select is(pg_temp.n('product_variant.purged'), 1, 'purge records product_variant.purged');
select is(better_supabase.purge_product(current_setting('t.p')::uuid), true, 'purge deletes a product');
select is(pg_temp.n('product.purged'), 1, 'purge records product.purged');

select * from finish();
rollback;
