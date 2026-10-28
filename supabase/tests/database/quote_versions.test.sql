-- Quote documents on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) prices a quote with prices that include tax, a document
-- discount and an optional line, and sends it. Sending publishes a frozen
-- version. A client signed in as a guest (…00e1) with a grant on the quote
-- reads it in the portal and accepts it with the optional line, and the
-- answer records who decided and from where. Globex (…0002) sees none of it.
begin;
select plan(16);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'buyer@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.quote', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Fit-out", "currency": "EUR", "pricesIncludeTax": true, "discountAmount": "1000", "depositBps": 3000}',
  '[{"section": "Work", "description": "Install", "unitAmount": "12100", "taxRateBps": 2100},
    {"section": "Work", "description": "Books", "quantity": 2, "unitAmount": "5450", "taxRateBps": 900},
    {"section": "Extras", "description": "Support", "unitAmount": "10000", "taxRateBps": 2100, "optional": true}]'
)::text, true);
select set_config('test.id', current_setting('test.quote')::jsonb ->> 'id', true);

select is(
  (select jsonb_build_array(x ->> 'list_total', x ->> 'discount_total', x ->> 'tax_total', x ->> 'total', x ->> 'deposit_due')
   from (select current_setting('test.quote')::jsonb as x) q),
  '["23000", "1000", "2870", "22000", "6600"]'::jsonb,
  'the totals leave out the optional line and spread the discount before tax'
);
select is(
  (select array_agg(t.discount order by t.tax_rate_bps) from better_supabase.quote_tax_lines t
   where t.parent_id = current_setting('test.id')::uuid),
  array[474, 526]::bigint[],
  'each rate carries its share of the discount'
);
select is(
  (select count(*)::int from better_supabase.quote_versions v where v.quote_id = current_setting('test.id')::uuid),
  0,
  'a draft has no published version'
);

select is(
  (better_supabase.send_quote(current_setting('test.id')::uuid) ->> 'revision')::int,
  1,
  'sending publishes revision 1'
);
select is(
  better_supabase.quote_version(current_setting('test.id')::uuid, 1) ->> 'total',
  '22000',
  'the published version keeps the sent total'
);
select throws_ok(
  format($$select better_supabase.update_quote(%L, '{"title": "Changed"}')$$, current_setting('test.id')),
  '55000',
  'only a draft quote, or one with changes requested, can change',
  'a sent quote is not edited in place'
);
select throws_ok(
  format($$select better_supabase.quote_version(%L, 9)$$, current_setting('test.id')),
  'P0002',
  'this quote has no such version',
  'an unknown revision is not found'
);

reset role;
select throws_ok(
  format($$update better_supabase.quote_versions set total = 0 where quote_id = %L$$, current_setting('test.id')),
  '55000',
  'a published quote version never changes',
  'even the owner role cannot change a published version'
);

-- Another organization sees neither the quote nor its version.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select is(
  (select count(*)::int from better_supabase.quote_versions v where v.quote_id = current_setting('test.id')::uuid)
    + (select count(*)::int from better_supabase.quote_tax_lines t where t.parent_id = current_setting('test.id')::uuid),
  0,
  'another organization reads no versions or tax lines'
);

-- The admin shares the quote with the buyer as a guest.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.invite', better_supabase.invite_guest(
  '00000000-0000-4000-8000-000000000001', 'buyer@example.test', 'Buyer'
)::text, true);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select better_supabase.accept_guest_invite(current_setting('test.invite')::jsonb ->> 'token');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select lives_ok(
  format($$select better_supabase.grant_guest_access(%L, 'quote', %L)$$,
    current_setting('test.invite')::jsonb ->> 'id', current_setting('test.id')),
  'the admin grants the guest the quote'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
select set_config('request.headers', '{"x-forwarded-for": "203.0.113.9, 198.51.100.4", "user-agent": "Browser/1"}', true);
set local role authenticated;

select is(
  better_supabase.portal_quote(current_setting('test.id')::uuid) ->> 'status',
  'viewed',
  'the guest opens the quote in the portal'
);
select is(
  (select count(*)::int from better_supabase.quote_versions v where v.quote_id = current_setting('test.id')::uuid),
  1,
  'a guest reads the versions of a quote shared with them'
);
select throws_ok(
  format($$select better_supabase.respond_to_portal_quote(%L, 'accepted', 'Els Jansen', null, '[1]')$$, current_setting('test.id')),
  '22023',
  'pick optional lines of this quote by position',
  'the guest can only pick optional lines'
);
select is(
  better_supabase.respond_to_portal_quote(current_setting('test.id')::uuid, 'accepted', 'Els Jansen', null, '[3]') ->> 'status',
  'accepted',
  'the guest accepts with the optional line'
);

reset role;
select is(
  (select (q.total, q.decided_by, q.decided_user_id, q.decided_ip, q.decided_user_agent)::text
   from better_supabase.quotes q where q.id = current_setting('test.id')::uuid),
  '(32000,"Els Jansen",00000000-0000-4000-8000-0000000000e1,198.51.100.4,Browser/1)',
  'the answer records the total, the name, the signed-in user, the IP and the user agent'
);
select is(
  (select v.total from better_supabase.quote_versions v where v.quote_id = current_setting('test.id')::uuid and v.revision = 1),
  22000::bigint,
  'accepting leaves the published version as it was sent'
);

select * from finish();
rollback;
