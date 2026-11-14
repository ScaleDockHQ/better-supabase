-- Example app rows (apps/examples/nextjs): the unibox channels, macros and drafts,
-- then the rest of the demo. Runs after seed.sql, which holds the library seed
-- that the pgTAP suite runs on.

-- The other channels of the unibox: email, Slack and WhatsApp inboxes with a
-- few conversations each, macros for the composer and one AI draft. They are
-- recorded as the channel adapters would record them; the simulator on /inbox
-- adds more. The WhatsApp conversation's last message is two days old, so its
-- 24 hour reply window is closed.
insert into better_supabase.inboxes (id, tenant_id, name, channel, bot_mode, settings) values
  ('00000000-0000-4000-8000-00000000e002', '00000000-0000-4000-8000-000000000001', 'Support email', 'email', 'human', '{"simulator": true}'),
  ('00000000-0000-4000-8000-00000000e003', '00000000-0000-4000-8000-000000000001', 'Acme Slack', 'slack', 'human', '{"simulator": true}'),
  ('00000000-0000-4000-8000-00000000e004', '00000000-0000-4000-8000-000000000001', 'WhatsApp support', 'whatsapp', 'human', '{"simulator": true}');

select better_supabase.record_inbound(jsonb_build_object(
  'inbox_id', '00000000-0000-4000-8000-00000000e002',
  'thread_id', 'sim:email:wile@acme-roadrunner.test',
  'subject', 'Invoice 1042 is overdue',
  'contact', jsonb_build_object('external_id', 'wile@acme-roadrunner.test', 'name', 'Wile E. Coyote', 'email', 'wile@acme-roadrunner.test'),
  'message', jsonb_build_object('body', 'Invoice 1042 shows as overdue, but we paid it last week. Can you check?')
));

select better_supabase.record_inbound(jsonb_build_object(
  'inbox_id', '00000000-0000-4000-8000-00000000e003',
  'thread_id', 'sim:slack:C0ACME:1',
  'subject', 'Shared channel: onboarding questions',
  'contact', jsonb_build_object('external_id', 'U0BEEP', 'name', 'Beep Beep', 'email', 'beep@roadrunner.test'),
  'message', jsonb_build_object('body', 'Who can set up SSO for our team?')
));

select better_supabase.record_inbound(jsonb_build_object(
  'inbox_id', '00000000-0000-4000-8000-00000000e004',
  'thread_id', 'sim:whatsapp:31612345678',
  'subject', 'Delivery question',
  'contact', jsonb_build_object('external_id', '31612345678', 'name', 'Daffy', 'phone', '+31612345678'),
  'message', jsonb_build_object('body', 'Is my order on its way?')
));

update better_supabase.inbox_conversations c
set last_inbound_at = now() - interval '2 days',
    last_message_at = now() - interval '2 days',
    created_at = now() - interval '2 days'
where c.thread_id = 'sim:whatsapp:31612345678';

update better_supabase.messages m
set sent_at = now() - interval '2 days',
    created_at = now() - interval '2 days'
from better_supabase.inbox_conversations c
where m.conversation_id = c.id
  and c.thread_id = 'sim:whatsapp:31612345678';

insert into better_supabase.inbox_message_templates (tenant_id, inbox_id, name, channel, language, body) values
  ('00000000-0000-4000-8000-000000000001', null, 'Thanks and next steps', 'in_app', 'en', 'Thanks for getting in touch. We are looking into it and will reply here today.'),
  ('00000000-0000-4000-8000-000000000001', null, 'Thanks and next steps', 'email', 'en', 'Hello,\n\nThanks for getting in touch. We are looking into it and will reply today.\n\nAcme support'),
  ('00000000-0000-4000-8000-000000000001', null, 'Invoice paid', 'email', 'en', 'Thanks for letting us know. We found your payment and marked the invoice as paid.'),
  ('00000000-0000-4000-8000-000000000001', null, 'Order update', 'whatsapp', 'en', 'Hello, this is Acme support with an update on your order. Reply here if you have questions.'),
  ('00000000-0000-4000-8000-000000000001', null, 'Thanks and next steps', 'slack', 'en', 'Thanks, we will look into this and answer in this thread.');

insert into better_supabase.inbox_drafts (tenant_id, conversation_id, source, input)
select c.tenant_id, c.id, 'ai',
  jsonb_build_object('body', 'Thanks for flagging this. I checked the invoice and corrected the VAT number. A new copy is on its way to you.', 'kind', 'message')
from better_supabase.inbox_conversations c
where c.thread_id = 'inbox:seed-road-runner';


-- The sales area (/crm). The permissions block's defaults do not list the
-- commissions and referrals keys, so the catalog gets them here and the
-- owner and admin roles hold all three of each; members keep their own
-- referral codes and commissions through the row policies.
insert into better_supabase.permissions (key)
select v.key
from (values
  ('commissions.read'), ('commissions.write'), ('commissions.manage'),
  ('referrals.read'), ('referrals.write'), ('referrals.manage')
) as v(key)
where not exists (select 1 from better_supabase.permissions p where p.key = v.key);

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
cross join better_supabase.permissions p
where r.key in ('owner', 'admin')
  and (p.key like 'commissions.%' or p.key like 'referrals.%')
on conflict do nothing;

-- Four companies, one per lifecycle stage the segment and score examples use.
insert into better_supabase.companies (id, tenant_id, name, domain, lifecycle, owner_id, created_by) values
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-000000000001', 'Globex', 'globex.test', 'customer', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000c0002', '00000000-0000-4000-8000-000000000001', 'Initech', 'initech.test', 'opportunity', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000c0003', '00000000-0000-4000-8000-000000000001', 'Hooli', 'hooli.test', 'lead', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000c0004', '00000000-0000-4000-8000-000000000001', 'Umbrella', 'umbrella.test', 'churned', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a1');

-- The block functions below check the caller's permissions; the seed runs
-- them as the Acme owner, with the service role where a function asks for it.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

-- The Sales deal pipeline with the six stages the app's default creates, and
-- a second pipeline for renewals.
select better_supabase.save_pipeline('00000000-0000-4000-8000-000000000001', null, 'deal', 'sales', 'Sales', null, true);
select better_supabase.save_pipeline('00000000-0000-4000-8000-000000000001', null, 'deal', 'renewals', 'Renewals', null, false);

select better_supabase.save_pipeline_stage(p.id, null, s.key, s.name, s.category, s.probability, null, null, null, null)
from better_supabase.pipelines p
cross join (values
  (1, 'qualified', 'Qualified', 'open', 20),
  (2, 'discovery', 'Discovery', 'open', 35),
  (3, 'proposal', 'Proposal', 'open', 55),
  (4, 'negotiation', 'Negotiation', 'open', 75),
  (5, 'won', 'Closed won', 'won', 100),
  (6, 'lost', 'Closed lost', 'lost', 0)
) as s(position, key, name, category, probability)
where p.key = 'sales' and p.tenant_id = '00000000-0000-4000-8000-000000000001'
order by s.position;

select better_supabase.save_pipeline_stage(p.id, null, s.key, s.name, s.category, s.probability, null, null, null, null)
from better_supabase.pipelines p
cross join (values
  (1, 'upcoming', 'Upcoming', 'open', 80),
  (2, 'renewed', 'Renewed', 'won', 100),
  (3, 'churned', 'Churned', 'lost', 0)
) as s(position, key, name, category, probability)
where p.key = 'renewals' and p.tenant_id = '00000000-0000-4000-8000-000000000001'
order by s.position;

-- Six deals across the stages, linked to the companies. The numbers follow
-- create_deal's DEAL-<n> per organization.
insert into better_supabase.deals (id, tenant_id, number, identifier, name, company_type, company_id, owner_id, amount, currency, pipeline_id, stage_id, stage_entered_at, probability, forecast_category, opened_on, expected_close_on, outcome, closed_at, created_by)
select d.id, '00000000-0000-4000-8000-000000000001', d.number, 'DEAL-' || d.number, d.name, 'company', d.company_id,
  d.owner_id, d.amount, 'EUR', p.id, st.id, now() - d.age, st.probability,
  d.category,
  current_date - 30, d.close_on,
  case st.category when 'won' then 'won' when 'lost' then 'lost' else 'open' end,
  case when st.category in ('won', 'lost') then now() - d.age end,
  '00000000-0000-4000-8000-0000000000a1'
from (values
  ('00000000-0000-4000-8000-0000000d0001'::uuid, 1, 'Annual plan for Globex', '00000000-0000-4000-8000-0000000c0001'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 1200000::bigint, 'negotiation', 'commit', current_date + 12, interval '4 days'),
  ('00000000-0000-4000-8000-0000000d0002', 2, 'Initech rollout', '00000000-0000-4000-8000-0000000c0002', '00000000-0000-4000-8000-0000000000a1', 840000, 'proposal', 'best_case', current_date + 25, interval '9 days'),
  ('00000000-0000-4000-8000-0000000d0003', 3, 'Hooli pilot', '00000000-0000-4000-8000-0000000c0003', '00000000-0000-4000-8000-0000000000a2', 300000, 'discovery', 'pipeline', current_date + 40, interval '2 days'),
  ('00000000-0000-4000-8000-0000000d0004', 4, 'Hooli seats expansion', '00000000-0000-4000-8000-0000000c0003', '00000000-0000-4000-8000-0000000000a2', 150000, 'qualified', 'pipeline', current_date + 55, interval '1 day'),
  ('00000000-0000-4000-8000-0000000d0005', 5, 'Globex add-on', '00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-0000000000a1', 450000, 'won', 'commit', current_date - 6, interval '6 days'),
  ('00000000-0000-4000-8000-0000000d0006', 6, 'Umbrella renewal', '00000000-0000-4000-8000-0000000c0004', '00000000-0000-4000-8000-0000000000a2', 220000, 'lost', 'omit', current_date - 12, interval '12 days')
) as d(id, number, name, company_id, owner_id, amount, stage_key, category, close_on, age)
join better_supabase.pipelines p on p.key = 'sales' and p.tenant_id = '00000000-0000-4000-8000-000000000001'
join better_supabase.pipeline_stages st on st.pipeline_id = p.id and st.key = d.stage_key;

-- Wile, the contact of the invoice conversation in the inbox, is a person on the
-- Initech rollout, so the inbox's context pane lists that deal.
insert into better_supabase.deal_contacts (tenant_id, deal_id, contact_type, contact_id, role, is_primary)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000d0002', 'person', p.id::text, 'Billing', true
from better_supabase.people p
where p.tenant_id = '00000000-0000-4000-8000-000000000001' and p.email = 'wile@acme-roadrunner.test';

-- The company field the segments and the score model test; the app writes the
-- same catalog at start-up (features/rules/sync-rule-fields.ts).
select better_supabase.sync_rule_fields('company', jsonb_build_array(jsonb_build_object(
  'id', 'lifecycle', 'type', 'select', 'nullable', false,
  'options', jsonb_build_array('lead', 'mql', 'sql', 'opportunity', 'customer', 'churned'),
  'operators', jsonb_build_array('is', 'is_not'))));

-- Segments, an assignment queue and a score model over the companies.
select better_supabase.save_segment('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'name', 'Customers', 'description', 'Companies that bought.', 'subjectType', 'company',
  'conditions', jsonb_build_object('id', 'root', 'type', 'group', 'combinator', 'and', 'rules', jsonb_build_array(
    jsonb_build_object('id', 'lifecycle', 'type', 'rule', 'path', jsonb_build_array('lifecycle'), 'operator', 'is', 'value', 'customer')))));
select better_supabase.save_segment('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'name', 'Open leads', 'description', 'Companies still being qualified.', 'subjectType', 'company',
  'conditions', jsonb_build_object('id', 'root', 'type', 'group', 'combinator', 'and', 'rules', jsonb_build_array(
    jsonb_build_object('id', 'lifecycle', 'type', 'rule', 'path', jsonb_build_array('lifecycle'), 'operator', 'is', 'value', 'lead')))));

select better_supabase.save_assignment_queue('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'name', 'New companies', 'subjectType', 'company', 'strategy', 'round_robin', 'rank', 0));

select better_supabase.set_assignment_members(q.id, jsonb_build_array(
  jsonb_build_object('userId', '00000000-0000-4000-8000-0000000000a1', 'weight', 1),
  jsonb_build_object('userId', '00000000-0000-4000-8000-0000000000a2', 'weight', 1)))
from better_supabase.assignment_queues q
where q.name = 'New companies' and q.tenant_id = '00000000-0000-4000-8000-000000000001';

select better_supabase.save_score_model('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'key', 'health', 'name', 'Account health', 'subjectType', 'company',
  'rules', jsonb_build_array(
    jsonb_build_object('id', 'customer', 'label', 'customer', 'points', 60, 'conditions', jsonb_build_object('id', 'root', 'type', 'group', 'combinator', 'and', 'rules', jsonb_build_array(
      jsonb_build_object('id', 'r1', 'type', 'rule', 'path', jsonb_build_array('lifecycle'), 'operator', 'is', 'value', 'customer')))),
    jsonb_build_object('id', 'opportunity', 'label', 'opportunity', 'points', 40, 'conditions', jsonb_build_object('id', 'root', 'type', 'group', 'combinator', 'and', 'rules', jsonb_build_array(
      jsonb_build_object('id', 'r1', 'type', 'rule', 'path', jsonb_build_array('lifecycle'), 'operator', 'is', 'value', 'opportunity'))))),
  'bands', jsonb_build_array(
    jsonb_build_object('label', 'cold', 'min', 0),
    jsonb_build_object('label', 'warm', 'min', 30),
    jsonb_build_object('label', 'hot', 'min', 60))));

select better_supabase.compute_score('00000000-0000-4000-8000-000000000001', 'health', 'company', c.id::text,
  jsonb_build_object('lifecycle', c.lifecycle), null)
from better_supabase.companies c
where c.tenant_id = '00000000-0000-4000-8000-000000000001';

select better_supabase.refresh_segment(sg.id)
from better_supabase.segments sg
where sg.tenant_id = '00000000-0000-4000-8000-000000000001';

-- Three draft contracts, and the forecast snapshot of the open quarter.
select better_supabase.create_contract('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'title', 'Globex master services agreement', 'counterpartyType', 'company', 'counterpartyId', '00000000-0000-4000-8000-0000000c0001',
  'ownerId', '00000000-0000-4000-8000-0000000000a1', 'value', 1200000, 'currency', 'EUR',
  'startsOn', (current_date - 90)::text, 'endsOn', (current_date + 275)::text, 'autoRenew', true, 'renewalMonths', 12, 'noticeDays', 60));
select better_supabase.create_contract('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'title', 'Initech pilot terms', 'counterpartyType', 'company', 'counterpartyId', '00000000-0000-4000-8000-0000000c0002',
  'ownerId', '00000000-0000-4000-8000-0000000000a1', 'value', 840000, 'currency', 'EUR',
  'startsOn', (current_date + 14)::text, 'endsOn', (current_date + 379)::text, 'autoRenew', false));
select better_supabase.create_contract('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'title', 'Hooli NDA', 'counterpartyType', 'company', 'counterpartyId', '00000000-0000-4000-8000-0000000c0003',
  'ownerId', '00000000-0000-4000-8000-0000000000a2',
  'startsOn', (current_date - 20)::text, 'endsOn', (current_date + 345)::text, 'autoRenew', false));

select better_supabase.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', p.id,
  date_trunc('quarter', current_date)::date, (date_trunc('quarter', current_date) + interval '3 months - 1 day')::date, 'EUR', 3000000)
from better_supabase.pipelines p
where p.key = 'sales' and p.tenant_id = '00000000-0000-4000-8000-000000000001';

-- Commission plans, their assignments and accrued commissions per rep, and
-- one referral code with a referral attributed to it.
select better_supabase.save_commission_plan('00000000-0000-4000-8000-000000000001', 'Standard 5 percent', 'flat', 500, null, null, false);
select better_supabase.save_commission_plan('00000000-0000-4000-8000-000000000001', 'Tiered quota', 'tiered', null,
  '[{"upTo": 1000000, "bps": 300}, {"bps": 600}]'::jsonb, null, false);

select better_supabase.assign_commission_plan('00000000-0000-4000-8000-000000000001', plan.id, s.seller_id, null, null, current_date - 60, null)
from better_supabase.commission_plans plan
join (values ('Standard 5 percent', '00000000-0000-4000-8000-0000000000a1'::uuid), ('Tiered quota', '00000000-0000-4000-8000-0000000000a2'::uuid)) as s(plan_name, seller_id)
  on s.plan_name = plan.name
where plan.tenant_id = '00000000-0000-4000-8000-000000000001';

select better_supabase.accrue_commission('00000000-0000-4000-8000-000000000001', v.seller_id, 'deal', v.deal_id, v.basis, 'EUR', v.on_day, null, null)
from (values
  ('00000000-0000-4000-8000-0000000000a1'::uuid, '00000000-0000-4000-8000-0000000d0005', 450000::bigint, current_date - 6),
  ('00000000-0000-4000-8000-0000000000a2'::uuid, '00000000-0000-4000-8000-0000000d0003', 300000::bigint, current_date - 3)
) as v(seller_id, deal_id, basis, on_day);

select better_supabase.create_referral_code('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
  'ACMEFRIENDS', null, 2500, 'EUR', 10, null);
select better_supabase.attribute_referral('00000000-0000-4000-8000-000000000001', 'ACMEFRIENDS', null, null, 'friend@initech.test');

-- The public store (/store/acme) and the stock ledger behind /shop/inventory:
-- five active products, one draft the store hides, two locations, a lot-tracked
-- coffee with two expiry dates and a published storefront.
insert into better_supabase.products (id, tenant_id, slug, title, description, kind, status, manufacturer) values
  ('00000000-0000-4000-8000-0000000b0001', '00000000-0000-4000-8000-000000000001', 'espresso-beans', 'Espresso beans, 1 kg', 'A dark roast with notes of cocoa and orange peel, roasted every week.', 'physical', 'active', 'Acme Roasters'),
  ('00000000-0000-4000-8000-0000000b0002', '00000000-0000-4000-8000-000000000001', 'ceramic-mug', 'Ceramic mug', 'A 300 ml stoneware mug that goes in the dishwasher.', 'physical', 'active', 'Acme Studio'),
  ('00000000-0000-4000-8000-0000000b0003', '00000000-0000-4000-8000-000000000001', 'steel-filter', 'Reusable steel filter', 'A fine mesh filter that replaces paper for 500 brews.', 'physical', 'active', 'Acme Studio'),
  ('00000000-0000-4000-8000-0000000b0004', '00000000-0000-4000-8000-000000000001', 'burr-grinder', 'Burr grinder Pro', 'A conical burr grinder with 40 settings.', 'physical', 'active', 'Acme Studio'),
  ('00000000-0000-4000-8000-0000000b0005', '00000000-0000-4000-8000-000000000001', 'gift-card', 'Gift card', 'A digital gift card, sent by email.', 'digital', 'active', null),
  ('00000000-0000-4000-8000-0000000b0006', '00000000-0000-4000-8000-000000000001', 'prototype-scale', 'Prototype scale', 'Not for sale yet.', 'physical', 'draft', null);

insert into better_supabase.product_variants (id, tenant_id, product_id, sku, title, track_inventory) values
  ('00000000-0000-4000-8000-0000000b1001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b0001', 'BEANS-1KG', '1 kg', true),
  ('00000000-0000-4000-8000-0000000b1002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b0002', 'MUG-CER', 'White', true),
  ('00000000-0000-4000-8000-0000000b1003', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b0003', 'FILTER-STEEL', null, true),
  ('00000000-0000-4000-8000-0000000b1004', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b0004', 'GRINDER-PRO', null, true),
  ('00000000-0000-4000-8000-0000000b1005', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b0005', 'GIFT-50', 'EUR 50', false),
  ('00000000-0000-4000-8000-0000000b1006', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b0006', 'SCALE-PROTO', null, true);

insert into better_supabase.product_prices (tenant_id, variant_id, currency, amount, compare_at_amount) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b1001', 'EUR', 1850, 2100),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b1002', 'EUR', 1200, null),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b1003', 'EUR', 900, null),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b1004', 'EUR', 12900, null),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b1005', 'EUR', 5000, null),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000b1006', 'EUR', 4900, null);

insert into better_supabase.catalog_storefronts (tenant_id, published_at) values
  ('00000000-0000-4000-8000-000000000001', now());

insert into better_supabase.inventory_locations (id, tenant_id, code, name, kind) values
  ('00000000-0000-4000-8000-0000000b2001', '00000000-0000-4000-8000-000000000001', 'MAIN', 'Main warehouse', 'warehouse'),
  ('00000000-0000-4000-8000-0000000b2002', '00000000-0000-4000-8000-000000000001', 'STORE', 'Amsterdam store', 'store');

select better_supabase.set_stock_item('00000000-0000-4000-8000-0000000b1001', 'item', 0::smallint, 'lot', true, 'none', null);
select better_supabase.save_lot('00000000-0000-4000-8000-0000000b1001', 'BEANS-2611', current_date + 25);
select better_supabase.save_lot('00000000-0000-4000-8000-0000000b1001', 'BEANS-2701', current_date + 120);

select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1001', '00000000-0000-4000-8000-0000000b2001', 40, 'receipt', 'First delivery', jsonb_build_object('lotId', (select id from better_supabase.stock_lots where code = 'BEANS-2611')));
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1001', '00000000-0000-4000-8000-0000000b2001', 60, 'receipt', 'Second delivery', jsonb_build_object('lotId', (select id from better_supabase.stock_lots where code = 'BEANS-2701')));
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1001', '00000000-0000-4000-8000-0000000b2001', -3, 'damage', 'Torn bag', jsonb_build_object('lotId', (select id from better_supabase.stock_lots where code = 'BEANS-2611')));
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1002', '00000000-0000-4000-8000-0000000b2001', 120, 'receipt', 'Pallet 14', null);
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1002', '00000000-0000-4000-8000-0000000b2002', 18, 'receipt', 'Moved to the shop floor', null);
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1002', '00000000-0000-4000-8000-0000000b2002', -2, 'loss', 'Dropped at the counter', null);
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1003', '00000000-0000-4000-8000-0000000b2001', 6, 'receipt', 'Sample batch', null);
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1004', '00000000-0000-4000-8000-0000000b2001', 4, 'receipt', 'Launch stock', null);
select better_supabase.adjust_stock('00000000-0000-4000-8000-0000000b1004', '00000000-0000-4000-8000-0000000b2001', -4, 'adjustment', 'Sold out at the launch event', null);

update better_supabase.stock_levels set reorder_point = 20, reorder_quantity = 60
where variant_id = '00000000-0000-4000-8000-0000000b1001';
update better_supabase.stock_levels set reorder_point = 10
where variant_id = '00000000-0000-4000-8000-0000000b1003';
update better_supabase.stock_levels set reorder_point = 2, reorder_quantity = 4
where variant_id = '00000000-0000-4000-8000-0000000b1004';

select set_config('request.jwt.claims', '', false);
-- The numbering page shows these sequences (finding EX-502).
insert into better_supabase.number_sequences (tenant_id, entity, period, last_number) values
  ('00000000-0000-4000-8000-000000000001', 'invoice', to_char(now(), 'YYYY'), 41),
  ('00000000-0000-4000-8000-000000000001', 'quote', to_char(now(), 'YYYY'), 17)
on conflict do nothing;

-- Phase 5 admin pages need rows to show (findings EX-509 to EX-512): security event
-- streams, OAuth clients, connector servers and a credit ledger.
insert into better_supabase.ssf_streams (id, tenant, receiver, audience, description, events_requested, events_delivered, delivery_method, status, verified_at)
values
  ('00000000-0000-4000-8000-0000005f0001', '00000000-0000-4000-8000-000000000001', 'https://siem.acme.test/ssf', array['https://acme.test'],
   'Session and credential events for the security team', array['https://schemas.openid.net/secevent/caep/event-type/session-revoked', 'https://schemas.openid.net/secevent/caep/event-type/credential-change'],
   array['https://schemas.openid.net/secevent/caep/event-type/session-revoked', 'https://schemas.openid.net/secevent/caep/event-type/credential-change'],
   'urn:ietf:rfc:8935', 'enabled', now() - interval '2 days'),
  ('00000000-0000-4000-8000-0000005f0002', '00000000-0000-4000-8000-000000000001', 'https://idp.partner.test/ssf', array['https://acme.test'],
   'Partner identity provider, polled every minute', array['https://schemas.openid.net/secevent/risc/event-type/account-disabled'],
   array['https://schemas.openid.net/secevent/risc/event-type/account-disabled'],
   'urn:ietf:rfc:8936', 'paused', now() - interval '9 days'),
  ('00000000-0000-4000-8000-0000005f0003', '00000000-0000-4000-8000-000000000001', 'https://old-siem.acme.test/ssf', array['https://acme.test'],
   'Retired receiver', array['https://schemas.openid.net/secevent/caep/event-type/session-revoked'],
   array[]::text[], 'urn:ietf:rfc:8935', 'disabled', null)
on conflict do nothing;

insert into auth.oauth_clients (id, registration_type, redirect_uris, grant_types, client_name, client_uri, client_type, token_endpoint_auth_method)
values
  ('00000000-0000-4000-8000-0000000a0a01', 'manual', 'https://app.acme.test/callback,https://app.acme.test/silent', 'authorization_code,refresh_token', 'Acme mobile app', 'https://acme.test', 'public', 'none'),
  ('00000000-0000-4000-8000-0000000a0a02', 'dynamic', 'https://claude.ai/api/mcp/auth_callback', 'authorization_code', 'Claude connector', 'https://claude.ai', 'public', 'none'),
  ('00000000-0000-4000-8000-0000000a0a03', 'manual', 'https://reports.acme.test/oauth/callback', 'authorization_code,client_credentials', 'Reporting service', 'https://reports.acme.test', 'confidential', 'client_secret_basic')
on conflict do nothing;

insert into better_supabase.connector_servers (id, tenant_id, name, url, transport, auth_type, scopes, enabled)
values
  ('00000000-0000-4000-8000-0000005c0001', '00000000-0000-4000-8000-000000000001', 'Docs search', 'https://mcp.acme.test/docs', 'http', 'oauth', array['docs.read'], true),
  ('00000000-0000-4000-8000-0000005c0002', '00000000-0000-4000-8000-000000000001', 'Ticket tracker', 'https://mcp.acme.test/tickets/sse', 'sse', 'none', array[]::text[], false)
on conflict do nothing;

-- A Vercel Marketplace installation linked to the first organization, with two
-- resources, so /settings/marketplace and its resource page render rows.
insert into better_supabase.marketplace_plans (id, name)
values ('free', 'Free'), ('pro', 'Pro')
on conflict do nothing;

insert into better_supabase.marketplace_installations (id, configuration_id, team_id, tenant, status)
values ('00000000-0000-4000-8000-0000000b0001', 'icfg_acme_demo', 'team_acme_demo', '00000000-0000-4000-8000-000000000001', 'active')
on conflict do nothing;

insert into better_supabase.marketplace_resources (id, installation_id, external_id, name, plan_id, status, tenant)
values
  ('00000000-0000-4000-8000-0000000b0011', '00000000-0000-4000-8000-0000000b0001', 'res_acme_primary', 'Primary database', 'pro', 'ready', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000b0012', '00000000-0000-4000-8000-0000000b0001', 'res_acme_staging', 'Staging database', 'free', 'pending', '00000000-0000-4000-8000-000000000001')
on conflict do nothing;

-- A credit ledger: one pool the organization buys credits into, one balance it spends from.
do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  pool uuid;
  balance uuid;
begin
  pool := (better_supabase.open_ledger_account(t, 'credit_pool', 'credits:pool', 'Credit purchases', 'credit', 0::smallint, null, null, null, true, null, null) ->> 'id')::uuid;
  balance := (better_supabase.open_ledger_account(t, 'credit_balance', 'credits:balance', 'AI credits', 'credit', 0::smallint, null, null, null, false, 'billing.read', null) ->> 'id')::uuid;

  perform better_supabase.ledger_post(t, 'credit.grant', jsonb_build_array(jsonb_build_object('account', pool, 'amount', -5000), jsonb_build_object('account', balance, 'amount', 5000)),
    'plan', 'pro', 'Monthly credits for the Pro plan', 'seed-credits-1', now() - interval '20 days');
  perform better_supabase.ledger_post(t, 'credit.usage', jsonb_build_array(jsonb_build_object('account', balance, 'amount', -1200), jsonb_build_object('account', pool, 'amount', 1200)),
    'ai_task', 'summaries', 'Meeting summaries', 'seed-credits-2', now() - interval '12 days');
  perform better_supabase.ledger_post(t, 'credit.purchase', jsonb_build_array(jsonb_build_object('account', pool, 'amount', -2000), jsonb_build_object('account', balance, 'amount', 2000)),
    'invoice', 'INV-0041', 'Top-up of 2,000 credits', 'seed-credits-3', now() - interval '6 days');
  perform better_supabase.ledger_post(t, 'credit.usage', jsonb_build_array(jsonb_build_object('account', balance, 'amount', -640), jsonb_build_object('account', pool, 'amount', 640)),
    'ai_task', 'drafts', 'Inbox reply drafts', 'seed-credits-4', now() - interval '2 days');
end $$;

-- Operations pages (phase 8c): maintenance plans with meters and calibrations,
-- requests for quotation with quotes and an award, laboratory samples with an
-- out of specification result, and till shifts with a closing count.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

select better_supabase.create_maintenance_meter('00000000-0000-4000-8000-000000000001', 'Forklift hours', 'h');
select better_supabase.create_maintenance_meter('00000000-0000-4000-8000-000000000001', 'Press cycles', 'cycles');

select better_supabase.record_meter_reading(m.id, v.reading)
from better_supabase.maintenance_meters m
join (values ('Forklift hours', 480), ('Press cycles', 12600)) as v(name, reading) on v.name = m.name
where m.tenant_id = '00000000-0000-4000-8000-000000000001';

select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', p.input)
from (values
  (jsonb_build_object('title', 'Forklift annual service', 'kind', 'time', 'everyDays', 365, 'priority', 'high',
    'parts', jsonb_build_array(jsonb_build_object('name', 'Hydraulic filter', 'quantity', 2), jsonb_build_object('name', 'Mast chain lubricant', 'quantity', 1)))),
  (jsonb_build_object('title', 'Fire extinguisher inspection', 'kind', 'time', 'everyDays', 30, 'priority', 'normal')),
  (jsonb_build_object('title', 'Dock door safety check', 'kind', 'time', 'everyDays', 14, 'priority', 'urgent')),
  (jsonb_build_object('title', 'HVAC filter replacement', 'kind', 'rrule', 'rrule', 'FREQ=MONTHLY;BYMONTHDAY=1', 'dtstart', date_trunc('month', now())::text, 'priority', 'low',
    'parts', jsonb_build_array(jsonb_build_object('name', 'G4 panel filter', 'quantity', 4)))),
  (jsonb_build_object('title', 'Conveyor belt tension', 'kind', 'time', 'everyDays', 60, 'priority', 'normal'))
) as p(input);

select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'title', 'Forklift oil change', 'kind', 'meter', 'meterId', m.id, 'everyValue', 250, 'priority', 'normal'))
from better_supabase.maintenance_meters m
where m.tenant_id = '00000000-0000-4000-8000-000000000001' and m.name = 'Forklift hours';

select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'title', 'Press lubrication', 'kind', 'meter', 'meterId', m.id, 'everyValue', 5000, 'priority', 'high'))
from better_supabase.maintenance_meters m
where m.tenant_id = '00000000-0000-4000-8000-000000000001' and m.name = 'Press cycles';

-- Two plans are overdue, and one of them already has its work order.
update better_supabase.maintenance_plans
set next_due_at = now() - interval '4 days'
where tenant_id = '00000000-0000-4000-8000-000000000001' and title = 'Fire extinguisher inspection';

select better_supabase.record_calibration('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'instrument', c.instrument, 'performedAt', (now() - c.age)::text, 'dueAt', (now() - c.age + c.every)::text,
  'result', c.result, 'reference', c.reference))
from (values
  ('Torque wrench TW-12', interval '300 days', interval '365 days', 'pass', 'CAL-2026-014'),
  ('Digital caliper DC-3', interval '40 days', interval '180 days', 'adjusted', 'CAL-2026-031'),
  ('Platform scale PS-1', interval '400 days', interval '365 days', 'pass', 'CAL-2025-007'),
  ('Pressure gauge PG-8', interval '20 days', interval '90 days', 'fail', 'CAL-2026-044')
) as c(instrument, age, every, result, reference);

select better_supabase.generate_maintenance_work_orders('00000000-0000-4000-8000-000000000001');

update better_supabase.maintenance_plans
set next_due_at = now() - interval '2 days'
where tenant_id = '00000000-0000-4000-8000-000000000001' and title = 'Dock door safety check';

do $seed$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  rfq jsonb;
  inv uuid;
  quote uuid;
  line_ids uuid[];
  supplier text;
  spec record;
  n int;
begin
  -- A draft, an open request with three quotes, and one awarded request.
  for spec in
    select * from (values
      ('Warehouse shelving, 12 bays', 'draft', 3),
      ('Forklift battery packs', 'open', 3),
      ('Packaging film, pallet wrap', 'awarded', 2)
    ) as x(title, target, suppliers)
  loop
    rfq := better_supabase.create_rfq(t,
      jsonb_build_object('title', spec.title, 'currency', 'EUR', 'dueAt', (now() + interval '14 days')::text,
        'notes', 'Delivery to the main warehouse, dock 2.'),
      jsonb_build_array(
        jsonb_build_object('description', spec.title || ' (standard)', 'quantity', 12),
        jsonb_build_object('description', spec.title || ' (spares)', 'quantity', 4)));

    if spec.target <> 'draft' then
      n := 0;
      for supplier in
        select c.id::text from better_supabase.companies c
        where c.tenant_id = t and c.merged_into is null order by c.id limit spec.suppliers
      loop
        perform better_supabase.invite_rfq_supplier((rfq ->> 'id')::uuid, 'company', supplier);
      end loop;
      perform better_supabase.open_rfq((rfq ->> 'id')::uuid);

      select array_agg(l.id order by l.ordinal) into line_ids from better_supabase.rfq_lines l where l.rfq_id = (rfq ->> 'id')::uuid;

      for inv in
        select s.id from better_supabase.rfq_suppliers s where s.rfq_id = (rfq ->> 'id')::uuid order by s.id
      loop
        n := n + 1;
        perform better_supabase.record_rfq_quote((rfq ->> 'id')::uuid, inv,
          jsonb_build_object('leadTimeDays', 5 + n * 3, 'validUntil', (current_date + 30)::text),
          jsonb_build_array(
            jsonb_build_object('lineId', line_ids[1], 'unitAmount', 9000 + n * 750),
            jsonb_build_object('lineId', line_ids[2], 'unitAmount', 4500 + n * 400)));
      end loop;

      if spec.target = 'awarded' then
        select q.id into quote from better_supabase.rfq_quotes q where q.rfq_id = (rfq ->> 'id')::uuid order by q.total_amount limit 1;
        perform better_supabase.award_rfq((rfq ->> 'id')::uuid, quote, null);
      end if;
    end if;
  end loop;
end
$seed$;

do $seed$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  ph uuid;
  assay uuid;
  moisture uuid;
  meter uuid;
  smp jsonb;
  sid uuid;
  spec record;
begin
  -- The laboratory's instrument holds a calibration qualification, which the
  -- block requires on every result.
  perform better_supabase.save_qualification_type(t, 'calibration', 'Calibration', array['asset'], 12);
  meter := (better_supabase.create_asset(t, 'instrument', 'Bench pH meter PH-100', null, 'LAB-PH-100') ->> 'id')::uuid;
  perform better_supabase.grant_qualification(t, 'calibration', 'asset', meter::text, current_date - 30);

  ph := (better_supabase.save_lims_method(t, jsonb_build_object('key', 'ph', 'name', 'pH', 'lowerLimit', 6, 'upperLimit', 8)) ->> 'id')::uuid;
  assay := (better_supabase.save_lims_method(t, jsonb_build_object('key', 'assay', 'name', 'Active ingredient', 'unit', '%', 'lowerLimit', 98, 'upperLimit', 102)) ->> 'id')::uuid;
  moisture := (better_supabase.save_lims_method(t, jsonb_build_object('key', 'moisture', 'name', 'Moisture', 'unit', '%', 'upperLimit', 5)) ->> 'id')::uuid;

  for spec in
    select * from (values
      ('Incoming raw material, lot RM-2044', 'raw material', 'RM-2044', 1, 'released'),
      ('Batch release, lot B-7781', 'finished product', 'B-7781', 3, 'completed'),
      ('Stability sample, lot B-7702', 'stability', 'B-7702', 6, 'testing'),
      ('Cleaning validation swab, line 2', 'swab', null, 8, 'testing_oos'),
      ('Water for injection, loop A', 'water', null, 10, 'registered'),
      ('Packaging component, lot PK-310', 'packaging', 'PK-310', 14, 'rejected'),
      ('Retained sample, lot B-7650', 'retained', 'B-7650', 20, 'registered')
    ) as x(title, kind, lot, age, target)
  loop
    smp := better_supabase.register_sample(t, jsonb_build_object('title', spec.title, 'kind', spec.kind,
      'lot', spec.lot, 'receivedOn', (current_date - spec.age)::text));
    sid := (smp ->> 'id')::uuid;

    if spec.target in ('released', 'completed') then
      perform better_supabase.record_lims_result(sid, ph, jsonb_build_object('value', 7.1, 'instrumentId', meter));
      perform better_supabase.record_lims_result(sid, assay, jsonb_build_object('value', 99.6, 'instrumentId', meter));
      perform better_supabase.complete_sample(sid);
      if spec.target = 'released' then
        perform better_supabase.release_sample(sid);
      end if;
    elsif spec.target = 'testing' then
      perform better_supabase.record_lims_result(sid, ph, jsonb_build_object('value', 6.8, 'instrumentId', meter));
    elsif spec.target = 'testing_oos' then
      perform better_supabase.record_lims_result(sid, moisture, jsonb_build_object('value', 6.4, 'note', 'Second run pending', 'instrumentId', meter));
      perform better_supabase.record_lims_result(sid, ph, jsonb_build_object('value', 5.2, 'instrumentId', meter));
    elsif spec.target = 'rejected' then
      perform better_supabase.reject_sample(sid, 'Damaged packaging on receipt');
    end if;
  end loop;
end
$seed$;

do $seed$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  front uuid;
  garden uuid;
  s uuid;
begin
  front := (better_supabase.create_till(t, jsonb_build_object('name', 'Front counter', 'currency', 'EUR', 'location', 'Store, entrance')) ->> 'id')::uuid;
  garden := (better_supabase.create_till(t, jsonb_build_object('name', 'Garden centre', 'currency', 'EUR', 'location', 'Store, garden centre')) ->> 'id')::uuid;
  perform better_supabase.create_till(t, jsonb_build_object('name', 'Pop-up stall', 'currency', 'EUR'));

  -- A closed shift with a count and a deposit.
  s := (better_supabase.open_till_session(front, 10000) ->> 'id')::uuid;
  perform better_supabase.record_till_movement(s, 'cash_sale', 8450, 'Morning sales');
  perform better_supabase.record_till_movement(s, 'cash_sale', 12390, 'Afternoon sales');
  perform better_supabase.record_till_movement(s, 'cash_refund', 1500, 'Returned jacket');
  perform better_supabase.record_till_movement(s, 'cash_out', 2000, 'Bank run: change');
  perform better_supabase.close_till_session(s, jsonb_build_object('denominations', jsonb_build_object('5000', 3, '2000', 5, '1000', 4, '500', 3, '100', 7), 'notes', 'Counted twice'));
  perform better_supabase.deposit_till_cash(s, jsonb_build_object('amount', 20000, 'reference', 'Deposit slip 4471'));

  -- A second closed shift, short in the drawer.
  s := (better_supabase.open_till_session(garden, 15000) ->> 'id')::uuid;
  perform better_supabase.record_till_movement(s, 'cash_sale', 6200, 'Plants and pots');
  perform better_supabase.close_till_session(s, jsonb_build_object('amount', 20900, 'notes', 'Drawer is 3 euro short'));

  -- An open shift with sales so far.
  s := (better_supabase.open_till_session(front, 10000) ->> 'id')::uuid;
  perform better_supabase.record_till_movement(s, 'cash_sale', 4300, 'Opening sales');
  perform better_supabase.record_till_movement(s, 'cash_in', 5000, 'Extra float');
end
$seed$;


-- A warehouse with bins, stock, putaway rules, pick lists in different states, a
-- wave and cycle count plans (the Warehouse pages read these).
do $seed$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  loc uuid;
  bin_a uuid;
  bin_b uuid;
  bin_c uuid;
  prod uuid;
  var uuid;
  vars uuid[] := '{}';
  spec record;
  list_id uuid;
  wave_id uuid;
  plan_id uuid;
  count_id uuid;
  line record;
begin
  -- The stock ledger seed above already made the main warehouse.
  select l.id into loc from better_supabase.inventory_locations l where l.tenant_id = t and l.code = 'MAIN';
  perform better_supabase.save_location(t, null, 'RET', 'Returns warehouse', null, null);
  bin_a := (better_supabase.save_bin(loc, null, 'A-01', 'Fast movers', false, true) ->> 'id')::uuid;
  bin_b := (better_supabase.save_bin(loc, null, 'B-04', 'Shelving', false, true) ->> 'id')::uuid;
  bin_c := (better_supabase.save_bin(loc, null, 'C-12', 'Overflow', false, true) ->> 'id')::uuid;
  perform better_supabase.save_bin_slot(t, jsonb_build_object('binId', bin_a, 'walkRank', 1, 'capacity', 200));
  perform better_supabase.save_bin_slot(t, jsonb_build_object('binId', bin_b, 'walkRank', 2, 'capacity', 500));
  perform better_supabase.save_bin_slot(t, jsonb_build_object('binId', bin_c, 'walkRank', 3));

  for spec in
    select * from (values
      ('Pallet wrap film', 'WH-WRAP', 120, 'A-01'),
      ('Cardboard box 40x30', 'WH-BOX-40', 300, 'B-04'),
      ('Shipping labels, roll', 'WH-LABEL', 80, 'A-01'),
      ('Bubble mailer', 'WH-MAILER', 220, 'C-12'),
      ('Strapping band', 'WH-STRAP', 60, 'C-12')
    ) as x(title, sku, qty, bin_code)
  loop
    prod := (better_supabase.save_product(t, null, spec.title, lower(spec.sku), null, 'physical', null) ->> 'id')::uuid;
    var := (better_supabase.save_variant(prod, null, spec.sku, null, spec.title, null, null, true, false, null) ->> 'id')::uuid;
    vars := vars || var;
    perform better_supabase.adjust_stock(var, loc, spec.qty, 'receipt', null,
      jsonb_build_object('binId', (select b.id from better_supabase.stock_bins b where b.location_id = loc and b.code = spec.bin_code)));
  end loop;

  perform better_supabase.save_putaway_rule(t, jsonb_build_object('locationId', loc, 'binId', bin_a, 'variantId', vars[1], 'priority', 10, 'maxQuantity', 150));
  perform better_supabase.save_putaway_rule(t, jsonb_build_object('locationId', loc, 'binId', bin_b, 'variantId', vars[2], 'priority', 10));
  perform better_supabase.save_putaway_rule(t, jsonb_build_object('locationId', loc, 'binId', bin_c, 'priority', 90));

  -- Pick lists for four orders: one open, one half picked, one done, one in a wave.
  for spec in select * from (values ('SO-1001', 'open'), ('SO-1002', 'partial'), ('SO-1003', 'done'), ('SO-1004', 'wave')) as x(doc, target)
  loop
    perform better_supabase.allocate_stock(t, vars[1], loc, 12, 'sales_order', spec.doc, 'l1', true);
    perform better_supabase.allocate_stock(t, vars[2], loc, 30, 'sales_order', spec.doc, 'l2', true);
    perform better_supabase.allocate_stock(t, vars[4], loc, 6, 'sales_order', spec.doc, 'l3', true);

    if spec.target = 'wave' then
      wave_id := (better_supabase.create_pick_wave(t, jsonb_build_object('name', 'Afternoon dispatch', 'locationId', loc)) ->> 'id')::uuid;
      list_id := (better_supabase.create_pick_list(t, jsonb_build_object('locationId', loc, 'documentType', 'sales_order', 'documentId', spec.doc, 'waveId', wave_id)) ->> 'id')::uuid;
      perform better_supabase.release_pick_wave(wave_id);
    else
      list_id := (better_supabase.create_pick_list(t, jsonb_build_object('locationId', loc, 'documentType', 'sales_order', 'documentId', spec.doc)) ->> 'id')::uuid;
    end if;

    if spec.target in ('partial', 'done') then
      for line in
        select l.id, l.quantity from better_supabase.pick_lines l where l.pick_list_id = list_id order by l.id
        limit case when spec.target = 'done' then 3 else 1 end
      loop
        perform better_supabase.record_pick(line.id, jsonb_build_object('quantity', line.quantity));
      end loop;
    end if;

    if spec.target = 'done' then
      perform better_supabase.complete_pick_list(list_id);
    end if;
  end loop;

  perform better_supabase.create_pick_wave(t, jsonb_build_object('name', 'Morning wave (draft)', 'locationId', loc));

  -- A plan that is due and has an open count, and one that is scheduled.
  plan_id := (better_supabase.create_count_plan(t, jsonb_build_object('name', 'Fast movers weekly', 'locationId', loc, 'everyDays', 7,
    'variantIds', jsonb_build_array(vars[1], vars[3]), 'varianceLimitPct', 5)) ->> 'id')::uuid;
  count_id := (better_supabase.run_count_plan(plan_id) ->> 'countId')::uuid;
  perform better_supabase.create_count_plan(t, jsonb_build_object('name', 'Full count, quarterly', 'locationId', loc, 'everyDays', 90,
    'startsOn', (current_date + 40)::text, 'varianceLimitPct', 2));
  perform better_supabase.create_count_plan(t, jsonb_build_object('name', 'Overflow bins monthly', 'locationId', loc, 'everyDays', 30,
    'startsOn', (current_date - 2)::text, 'variantIds', jsonb_build_array(vars[4], vars[5])));
end
$seed$;

-- People and work for Acme (EX-920): an org chart with contracts, leave types
-- and requests, an onboarding program with enrollments, a starter template,
-- qualifications with holders, and a week of shifts with assignments.
insert into better_supabase.employees (id, tenant_id, user_id, name, email, job_title, team_id, manager_id, status, start_date, created_by) values
  ('00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'Ada Admin', 'admin@acme.test', 'Managing director', null, null, 'active', current_date - 900, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000e0002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'Max Member', 'member@acme.test', 'Account executive', '00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000e0001', 'active', current_date - 400, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000e0003', '00000000-0000-4000-8000-000000000001', null, 'Priya Patel', 'priya@acme.test', 'Head of support', '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000e0001', 'active', current_date - 700, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000e0004', '00000000-0000-4000-8000-000000000001', null, 'Sam Okafor', 'sam@acme.test', 'Support agent', '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000e0003', 'active', current_date - 200, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000e0005', '00000000-0000-4000-8000-000000000001', null, 'Lena Fischer', 'lena@acme.test', 'Support agent', '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000e0003', 'on_leave', current_date - 300, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000e0006', '00000000-0000-4000-8000-000000000001', null, 'Noor Haddad', 'noor@acme.test', 'Sales development rep', '00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000e0002', 'preboarding', current_date + 14, '00000000-0000-4000-8000-0000000000a1');

insert into better_supabase.employee_contracts (tenant_id, employee_id, starts_on, hours_per_week, created_by)
select e.tenant_id, e.id, e.start_date, 40, '00000000-0000-4000-8000-0000000000a1'
from better_supabase.employees e where e.tenant_id = '00000000-0000-4000-8000-000000000001';

insert into better_supabase.leave_types (id, tenant_id, key, name, unit, paid, tracked, allowance, carryover_max, color) values
  ('00000000-0000-4000-8000-0000000e1001', '00000000-0000-4000-8000-000000000001', 'annual', 'Annual leave', 'days', true, true, 25, 5, '#2563eb'),
  ('00000000-0000-4000-8000-0000000e1002', '00000000-0000-4000-8000-000000000001', 'sick', 'Sick leave', 'days', true, false, null, null, '#dc2626'),
  ('00000000-0000-4000-8000-0000000e1003', '00000000-0000-4000-8000-000000000001', 'unpaid', 'Unpaid leave', 'days', false, false, null, null, '#6b7280');

insert into better_supabase.leave_requests (id, tenant_id, user_id, type_id, starts_on, ends_on, amount, note, approved_at) values
  ('00000000-0000-4000-8000-0000000e1101', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000e1002', current_date - 12, current_date - 11, 2, 'Flu', now() - interval '12 days'),
  ('00000000-0000-4000-8000-0000000e1102', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000e1003', current_date + 30, current_date + 31, 2, 'Moving house', null);

select better_supabase.save_enrollment_program('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'key', 'new-hire', 'name', 'New hire', 'description', 'What a new employee finishes in the first weeks.',
  'subjectTypes', jsonb_build_array('employee'),
  'steps', jsonb_build_array(
    jsonb_build_object('id', 'equipment', 'title', 'Hand over equipment', 'due', jsonb_build_object('days', 0, 'from', 'start')),
    jsonb_build_object('id', 'accounts', 'title', 'Create accounts', 'due', jsonb_build_object('days', 1, 'from', 'start')),
    jsonb_build_object('id', 'intro', 'title', 'Meet the team', 'due', jsonb_build_object('days', 7, 'from', 'start')),
    jsonb_build_object('id', 'review', 'title', 'First review', 'due', jsonb_build_object('days', 30, 'from', 'start')))));

select better_supabase.enrollment_ensure('00000000-0000-4000-8000-000000000001', 'new-hire', 1, array['equipment', 'accounts', 'intro', 'review'], 'employee', e.id::text, null)
from better_supabase.employees e
where e.tenant_id = '00000000-0000-4000-8000-000000000001' and e.id in ('00000000-0000-4000-8000-0000000e0004', '00000000-0000-4000-8000-0000000e0006');

select better_supabase.enrollment_mark(en.id, 'equipment', true, null)
from better_supabase.enrollments en
where en.tenant_id = '00000000-0000-4000-8000-000000000001' and en.program = 'new-hire' and en.subject_id = '00000000-0000-4000-8000-0000000e0004';

insert into better_supabase.document_templates (tenant_id, document_type, language, name, body) values
  ('00000000-0000-4000-8000-000000000001', 'invoice', 'en', 'standard', '<h1>Invoice</h1>'),
  ('00000000-0000-4000-8000-000000000001', 'invoice', 'nl', 'standard', '<h1>Factuur</h1>');

insert into better_supabase.qualification_types (id, tenant_id, key, name, description, holder_types, valid_for_months, evidence_required) values
  ('00000000-0000-4000-8000-0000000e2001', '00000000-0000-4000-8000-000000000001', 'first-aid', 'First aid', 'Basic first aid certificate.', array['member'], 24, false),
  ('00000000-0000-4000-8000-0000000e2002', '00000000-0000-4000-8000-000000000001', 'gdpr', 'GDPR awareness', 'Yearly privacy training.', array['member'], 12, false);

insert into better_supabase.qualification_requirements (tenant_id, type_id, target_type, target_value)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000e2001', 'role', 'member');

insert into better_supabase.qualifications (tenant_id, type_id, holder_type, holder_id, granted_on, expires_on, granted_by) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000e2001', 'member', '00000000-0000-4000-8000-0000000000a1', current_date - 300, current_date + 430, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000e2002', 'member', '00000000-0000-4000-8000-0000000000a1', current_date - 340, current_date + 25, '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000e2002', 'member', '00000000-0000-4000-8000-0000000000a2', current_date - 400, current_date - 35, '00000000-0000-4000-8000-0000000000a1');

insert into better_supabase.shifts (id, tenant_id, team_id, starts_at, ends_at, break_minutes, headcount, status, note, published_at, created_by)
select ('00000000-0000-4000-8000-0000000e3' || lpad(d::text, 3, '0'))::uuid, '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000e2',
  (date_trunc('week', now() at time zone 'UTC') + make_interval(days => d) + interval '8 hours') at time zone 'UTC',
  (date_trunc('week', now() at time zone 'UTC') + make_interval(days => d) + interval '16 hours') at time zone 'UTC',
  30, 2, case when d = 4 then 'draft' else 'published' end, case when d = 0 then 'Phones until noon, then tickets.' else null end,
  case when d = 4 then null else now() end, '00000000-0000-4000-8000-0000000000a1'
from generate_series(0, 4) d;

insert into better_supabase.shift_assignments (tenant_id, shift_id, user_id, starts_at, ends_at, status, assigned_by)
select s.tenant_id, s.id, u.user_id, s.starts_at, s.ends_at, u.status, '00000000-0000-4000-8000-0000000000a1'
from better_supabase.shifts s
join (values
  ('00000000-0000-4000-8000-0000000e3000'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 'assigned'),
  ('00000000-0000-4000-8000-0000000e3000', '00000000-0000-4000-8000-0000000000a2', 'assigned'),
  ('00000000-0000-4000-8000-0000000e3001', '00000000-0000-4000-8000-0000000000a2', 'assigned'),
  ('00000000-0000-4000-8000-0000000e3002', '00000000-0000-4000-8000-0000000000a1', 'requested')
) as u(shift_id, user_id, status) on u.shift_id = s.id;

-- The front desk calendar: a few visits today and in the coming days.
insert into better_supabase.calendars (id, tenant_id, name, tz, color) values
  ('00000000-0000-4000-8000-0000000e4001', '00000000-0000-4000-8000-000000000001', 'Front desk', 'UTC', '#2563eb');

insert into better_supabase.calendar_events (tenant_id, calendar_id, uid, title, location, starts_at, ends_at, created_by)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000e4001', 'seed-front-desk-' || v.n, v.title, v.location,
  (current_date + v.day + v.at)::timestamptz, (current_date + v.day + v.at + interval '45 minutes')::timestamptz,
  '00000000-0000-4000-8000-0000000000a1'
from (values
  (1, 0, interval '9 hours', 'Visit: Initech facilities', 'Reception'),
  (2, 0, interval '11 hours 30 minutes', 'Interview: support agent', 'Room 2'),
  (3, 0, interval '14 hours', 'Delivery: office supplies', 'Loading dock'),
  (4, 1, interval '10 hours', 'Visit: Globex auditors', 'Room 1'),
  (5, 3, interval '15 hours', 'Onboarding: Noor Haddad', 'Reception')
) as v(n, day, at, title, location);

-- A review cycle with a rubric, opened for two people (the reviews stay unwritten).
select better_supabase.open_appraisal_cycle((better_supabase.create_appraisal_cycle('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'name', 'Mid-year review', 'startsOn', (current_date - 30)::text, 'endsOn', (current_date + 60)::text,
  'competencies', jsonb_build_array(
    jsonb_build_object('key', 'delivery', 'name', 'Delivery', 'weight', 2),
    jsonb_build_object('key', 'teamwork', 'name', 'Teamwork', 'weight', 1)))) ->> 'id')::uuid,
  jsonb_build_array(
    jsonb_build_object('subjectUserId', '00000000-0000-4000-8000-0000000000a2', 'managerId', '00000000-0000-4000-8000-0000000000a1'),
    jsonb_build_object('subjectUserId', '00000000-0000-4000-8000-0000000000a1')));

select set_config('request.jwt.claims', '', false);
