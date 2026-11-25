-- Example app rows (apps/examples/nextjs): the unibox channels, macros and drafts,
-- then the rest of the demo. Runs after seed.sql, which holds the library seed
-- that the pgTAP suite runs on.

-- The other channels of the unibox: email, Slack and WhatsApp inboxes,
-- macros for the composer and one AI draft. Their conversations come from the
-- generated seed of the inbox page (`pnpm db:seed:pages`, which `supabase:reset`
-- runs): the WhatsApp one is two days old, so its 24 hour reply window is closed.
insert into better_supabase.inboxes (id, tenant_id, name, channel, bot_mode, settings) values
  ('00000000-0000-4000-8000-00000000e002', '00000000-0000-4000-8000-000000000001', 'Support email', 'email', 'human', '{"simulator": true}'),
  ('00000000-0000-4000-8000-00000000e003', '00000000-0000-4000-8000-000000000001', 'Acme Slack', 'slack', 'human', '{"simulator": true}'),
  ('00000000-0000-4000-8000-00000000e004', '00000000-0000-4000-8000-000000000001', 'WhatsApp support', 'whatsapp', 'human', '{"simulator": true}');

-- A WhatsApp webhook event the handler failed on, for the replay sheet on /inbox.
-- It has used all its attempts, so the pending queue skips it until someone replays it.
insert into better_supabase.inbox_inbound_events (tenant_id, adapter, external_id, inbox_id, body, status, error, attempts, received_at)
values (
  '00000000-0000-4000-8000-000000000001', 'whatsapp', 'wamid.seed-failed', '00000000-0000-4000-8000-00000000e004',
  '{"object":"whatsapp_business_account","entry":[]}', 'failed', 'The handler timed out', 5, now() - interval '3 hours'
);

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

-- The pipelines, deals, segments, assignment queue, score model and contracts of the
-- sales area are generated seeds of their pages (`pnpm db:seed:pages`, ADR 1035).

-- The company field the segments and the score model test; the app writes the
-- same catalog at start-up (features/rules/sync-rule-fields.ts).
select better_supabase.sync_rule_fields('company', jsonb_build_array(jsonb_build_object(
  'id', 'lifecycle', 'type', 'select', 'nullable', false,
  'options', jsonb_build_array('lead', 'mql', 'sql', 'opportunity', 'customer', 'churned'),
  'operators', jsonb_build_array('is', 'is_not'))));

-- Commission plans, their assignments per rep, and one referral code. The accrued
-- commissions and the referral attributed to the code are generated seeds of the
-- commissions and referrals pages (`pnpm db:seed:pages`, ADR 1032).
select better_supabase.save_commission_plan('00000000-0000-4000-8000-000000000001', 'Standard 5 percent', 'flat', 500, null, null, false);
select better_supabase.save_commission_plan('00000000-0000-4000-8000-000000000001', 'Tiered quota', 'tiered', null,
  '[{"upTo": 1000000, "bps": 300}, {"bps": 600}]'::jsonb, null, false);

select better_supabase.assign_commission_plan('00000000-0000-4000-8000-000000000001', plan.id, s.seller_id, null, null, current_date - 60, null)
from better_supabase.commission_plans plan
join (values ('Standard 5 percent', '00000000-0000-4000-8000-0000000000a1'::uuid), ('Tiered quota', '00000000-0000-4000-8000-0000000000a2'::uuid)) as s(plan_name, seller_id)
  on s.plan_name = plan.name
where plan.tenant_id = '00000000-0000-4000-8000-000000000001';

select better_supabase.create_referral_code('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
  'ACMEFRIENDS', null, 2500, 'EUR', 10, null);

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

-- Service and logistics story: a technician is on site with a forklift service
-- (complete it with "Complete visit"), a second visit waits in the day plan, and
-- three parcels sit at the three stages of tracking.
insert into better_supabase.work_orders (tenant_id, title, description, priority, status, technician_id, starts_at, ends_at,
  address, en_route_at, arrived_at, created_by)
select '00000000-0000-4000-8000-000000000001', v.title, v.description, v.priority, v.status,
  '00000000-0000-4000-8000-0000000000a1', now() + v.at, now() + v.at + interval '2 hours', v.address,
  case when v.status in ('en_route', 'on_site') then now() + v.at - interval '30 minutes' end,
  case when v.status = 'on_site' then now() + v.at - interval '10 minutes' end,
  '00000000-0000-4000-8000-0000000000a1'
from (values
  ('Forklift hydraulic service', 'Replace the hydraulic filter and log the hour meter.', 'high', 'on_site', interval '-1 hour', 'Keizersgracht 1, Amsterdam'),
  ('Dock door sensor check', 'Test the safety sensors on doors 3 and 4.', 'normal', 'scheduled', interval '3 hours', 'Loading dock, Rotterdam')
) as v(title, description, priority, status, at, address)
where not exists (
  select 1 from better_supabase.work_orders w
  where w.tenant_id = '00000000-0000-4000-8000-000000000001' and w.title = v.title);

with new_shipments as (
  insert into better_supabase.shipments (tenant_id, reference, status, from_address, to_address, direction, carrier, service,
    tracking_number, labeled_at, delivered_at, created_by)
  select '00000000-0000-4000-8000-000000000001', v.reference, v.status,
    '{"company": "Acme Rockets", "line1": "Keizersgracht 1", "city": "Amsterdam", "postalCode": "1015 CJ", "country": "NL"}'::jsonb,
    jsonb_build_object('name', v.recipient, 'line1', v.line1, 'city', v.city, 'postalCode', v.postal, 'country', 'NL'),
    'outbound', case when v.status <> 'draft' then 'PostNL' end, case when v.status <> 'draft' then 'Parcel' end,
    case when v.status <> 'draft' then 'SEED' || v.reference end,
    case when v.status <> 'draft' then now() - interval '2 days' end,
    case when v.status = 'delivered' then now() - interval '4 hours' end,
    '00000000-0000-4000-8000-0000000000a1'
  from (values
    ('SH-SEED-01', 'draft', 'Initech facilities', 'Spuistraat 10', 'Utrecht', '3511 AB'),
    ('SH-SEED-02', 'in_transit', 'Globex warehouse', 'Havenweg 4', 'Rotterdam', '3011 XY'),
    ('SH-SEED-03', 'delivered', 'Hooli reception', 'Stationsplein 2', 'Eindhoven', '5611 AB')
  ) as v(reference, status, recipient, line1, city, postal)
  where not exists (
    select 1 from better_supabase.shipments s
    where s.tenant_id = '00000000-0000-4000-8000-000000000001' and s.reference = v.reference)
  returning id, reference, status
), parcels as (
  insert into better_supabase.shipment_packages (tenant_id, shipment_id, position, weight_grams)
  select '00000000-0000-4000-8000-000000000001', id, 1, 2400 from new_shipments
)
insert into better_supabase.shipment_tracking_events (tenant_id, shipment_id, external_id, status, occurred_at, description, location, source)
select '00000000-0000-4000-8000-000000000001', n.id, 'seed-' || n.reference || '-' || e.step, e.status, now() - e.age, e.description, e.location, 'manual'
from new_shipments n
join (values
  ('in_transit', 1, 'label_created', interval '2 days', 'Label created', 'Amsterdam'),
  ('in_transit', 2, 'in_transit', interval '1 day', 'Picked up by the carrier', 'Amsterdam'),
  ('delivered', 1, 'label_created', interval '2 days', 'Label created', 'Amsterdam'),
  ('delivered', 2, 'in_transit', interval '30 hours', 'In sorting', 'Utrecht'),
  ('delivered', 3, 'delivered', interval '4 hours', 'Delivered to reception', 'Eindhoven')
) as e(for_status, step, status, age, description, location) on e.for_status = n.status;

-- Projects story: two projects with a budget, and tracked time on them (two billable
-- entries at an hourly rate and one internal), so the portfolio and the project
-- page show hours, billable value and what is left of the budget.
insert into public.projects (id, organization_id, name, budget_minor, currency, lead_id)
select v.id, '00000000-0000-4000-8000-000000000001', v.name, v.budget, 'EUR', '00000000-0000-4000-8000-0000000000a1'
from (values
  ('00000000-0000-4000-8000-00000000b001'::uuid, 'Warehouse automation rollout', 1500000::bigint),
  ('00000000-0000-4000-8000-00000000b002'::uuid, 'Customer portal refresh', 400000::bigint)
) as v(id, name, budget)
where not exists (select 1 from public.projects p where p.id = v.id);

insert into better_supabase.time_entries (tenant_id, user_id, subject_type, subject_id, started_at, ended_at, billable, rate, rate_currency, note)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'project', e.project, current_date - e.days + time '09:00', current_date - e.days + time '09:00' + (e.hours || ' hours')::interval, e.billable, e.rate, 'EUR', e.note
from (values
  ('00000000-0000-4000-8000-00000000b001', 45, 6, true, 9500::bigint, 'Dock layout workshop'),
  ('00000000-0000-4000-8000-00000000b001', 46, 4, true, 9500::bigint, 'Scanner integration'),
  ('00000000-0000-4000-8000-00000000b001', 47, 2, false, null::bigint, 'Internal planning')
) as e(project, days, hours, billable, rate, note)
where not exists (
  select 1 from better_supabase.time_entries t where t.subject_id = e.project and t.note = e.note
);

-- A member's submitted week, waiting on its approval request, so the portfolio's
-- "Time awaiting approval" card has a week to approve and invoice.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a2"}', false);

insert into better_supabase.time_entries (tenant_id, user_id, subject_type, subject_id, started_at, ended_at, billable, rate, rate_currency, note)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'project', '00000000-0000-4000-8000-00000000b002',
  date_trunc('week', current_date - 14) + time '09:00', date_trunc('week', current_date - 14) + time '14:00', true, 8500, 'EUR', 'Portal wireframes'
where not exists (select 1 from better_supabase.time_entries t where t.note = 'Portal wireframes');

select better_supabase.submit_timesheet('00000000-0000-4000-8000-000000000001', (current_date - 14)::date, 'Portal wireframes week')
where not exists (
  select 1 from better_supabase.timesheets s
  where s.user_id = '00000000-0000-4000-8000-0000000000a2' and s.week = date_trunc('week', current_date - 14)::date
);

select set_config('request.jwt.claims', '', false);

-- The content story: one live post, one scheduled page and a draft that
-- the entry page publishes with a version.
insert into better_supabase.content_entries (id, tenant_id, type, locale, slug, title, summary, body, status, publish_at, published_at, author_id, created_by) values
  ('00000000-0000-4000-8000-0000000d0001', '00000000-0000-4000-8000-000000000001', 'post', 'en', 'spring-launch', 'Spring launch notes', 'What shipped this quarter.', '{"blocks": [{"type": "paragraph", "text": "Spring launch notes."}]}', 'published', null, now() - interval '3 days', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000d0002', '00000000-0000-4000-8000-000000000001', 'page', 'en', 'pricing', 'Pricing', 'Plans and what each one includes.', '{"blocks": [{"type": "paragraph", "text": "Pricing."}]}', 'scheduled', now() + interval '5 days', null, '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000d0003', '00000000-0000-4000-8000-000000000001', 'post', 'en', 'summer-roadmap', 'Summer roadmap', 'What comes next.', '{"blocks": [{"type": "paragraph", "text": "Summer roadmap."}]}', 'draft', null, null, '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1')
on conflict do nothing;

-- The care story: two clients, a medication consent for the first only, a published
-- care plan with a problem and a goal, and a prescribed medication with a draft prescription.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

insert into public.customers (id, organization_id, name, status) values
  ('00000000-0000-4000-8000-0000000ca001', '00000000-0000-4000-8000-000000000001', 'Noor Haddad', 'active'),
  ('00000000-0000-4000-8000-0000000ca002', '00000000-0000-4000-8000-000000000001', 'Jan de Vries', 'active')
on conflict do nothing;

select better_supabase.save_consent_purpose('00000000-0000-4000-8000-000000000001', 'medication', 'Medication records', '1', 'Records and shares the medication chart of the client.', 'consent');
select better_supabase.record_consent('customer', '00000000-0000-4000-8000-0000000ca001', 'medication', 'granted');

select better_supabase.save_medication('00000000-0000-4000-8000-000000000001', 'Paracetamol', 'mg', 'custom', null, 'tablet', '500 mg');
select better_supabase.save_medication('00000000-0000-4000-8000-000000000001', 'Ibuprofen', 'mg', 'custom', null, 'tablet', '400 mg');

with plan as (
  select better_supabase.create_care_plan('00000000-0000-4000-8000-000000000001', jsonb_build_object(
    'subjectType', 'customer', 'subjectId', '00000000-0000-4000-8000-0000000ca001',
    'title', 'Mobility and pain plan', 'startsOn', current_date::text, 'reviewOn', (current_date + 42)::text)) as row
), problem as (
  select better_supabase.add_care_plan_problem((plan.row ->> 'id')::uuid, jsonb_build_object('title', 'Pain when walking', 'codeSystem', 'custom')) as row, plan.row as plan_row from plan
), goal as (
  select better_supabase.add_care_plan_goal((problem.row ->> 'id')::uuid, jsonb_build_object('title', 'Walk to the garden without pain')) as row, problem.plan_row from problem
)
select better_supabase.publish_care_plan((goal.plan_row ->> 'id')::uuid) from goal;

with med as (
  select id from better_supabase.medications where tenant_id = '00000000-0000-4000-8000-000000000001' and name = 'Paracetamol' limit 1
), ordered as (
  select better_supabase.prescribe_medication('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-0000000ca001', med.id,
    jsonb_build_object('dose', 500, 'route', 'oral', 'schedule', jsonb_build_object('times', jsonb_build_array('08:00', '20:00')))) as row from med
)
select better_supabase.create_prescription('00000000-0000-4000-8000-000000000001', (ordered.row ->> 'id')::uuid, jsonb_build_object('prescriberId', '00000000-0000-4000-8000-0000000000a1', 'prescriberName', 'Dr Kim'))
from ordered;

select set_config('request.jwt.claims', '', false);

-- Governance story: a supplier risk that is rated and mitigated, and two tracked
-- vulnerabilities, one of them critical. A matrix is created only when the
-- organization has none, so a seed that adds its own default keeps it.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

select better_supabase.save_risk_matrix(
  '00000000-0000-4000-8000-000000000001', 'story-matrix', '5 by 5 matrix',
  '[{"label":"Rare","value":1},{"label":"Unlikely","value":2},{"label":"Possible","value":3},{"label":"Likely","value":4},{"label":"Almost certain","value":5}]'::jsonb,
  '[{"label":"Insignificant","value":1},{"label":"Minor","value":2},{"label":"Moderate","value":3},{"label":"Major","value":4},{"label":"Severe","value":5}]'::jsonb,
  '[{"key":"low","min":1,"max":4,"label":"Low"},{"key":"medium","min":5,"max":9,"label":"Medium"},{"key":"high","min":10,"max":16,"label":"High"},{"key":"critical","min":17,"max":25,"label":"Critical"}]'::jsonb,
  'product', true, null)
where not exists (select 1 from better_supabase.risk_matrices where tenant_id = '00000000-0000-4000-8000-000000000001');

with created as (
  select better_supabase.create_risk('00000000-0000-4000-8000-000000000001', jsonb_build_object(
    'title', 'Payment provider outage', 'category', 'operational',
    'description', 'Checkout stops while the payment provider is down.',
    'cause', 'A single provider handles every card payment.',
    'consequence', 'Orders are lost for as long as the outage lasts.',
    'reviewIntervalMonths', 6)) as row
)
select better_supabase.assess_risk((created.row ->> 'id')::uuid, 4, 4, 2, 3, 'A second provider is on the roadmap.') from created;

select better_supabase.save_vulnerability('00000000-0000-4000-8000-000000000001', 'CVE-2026-31001', 'Remote code execution in the image resizer', null, null, null, '3.1', 9.8, null);
select better_supabase.save_vulnerability('00000000-0000-4000-8000-000000000001', 'CVE-2026-31002', 'Open redirect in the login callback', null, null, null, '3.1', 5.4, null);

select set_config('request.jwt.claims', '', false);

-- People story (/people/hiring, /courses): two open jobs and a draft, four
-- applications on different stages of the hiring pipeline, and a published course with one required lesson that
-- two employees are enrolled in. The onboarding program, leave and shifts above
-- complete the story. Run as the Acme owner, with the service role where a
-- function asks for it.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

do $$
declare
  v_tenant uuid := '00000000-0000-4000-8000-000000000001';
  v_support uuid;
  v_sales uuid;
  v_customers uuid[];
  v_course uuid;
  v_module uuid;
  v_pipeline uuid;
begin
  if exists (select 1 from better_supabase.job_openings j where j.tenant_id = v_tenant and j.title = 'Support agent') then
    return;
  end if;

  v_support := (better_supabase.save_job(v_tenant, null, jsonb_build_object(
    'title', 'Support agent', 'location', 'Amsterdam', 'employmentType', 'full_time',
    'description', 'Answer customers in the shared inbox and the helpdesk.', 'status', 'open')) ->> 'id')::uuid;
  v_sales := (better_supabase.save_job(v_tenant, null, jsonb_build_object(
    'title', 'Account executive', 'location', 'Remote', 'employmentType', 'full_time',
    'description', 'Own deals from first call to signed contract.', 'status', 'open')) ->> 'id')::uuid;
  perform better_supabase.save_job(v_tenant, null, jsonb_build_object(
    'title', 'Warehouse planner', 'location', 'Rotterdam', 'status', 'draft'));

  select array_agg(c.id order by c.name) into v_customers
  from (select id, name from public.customers where organization_id = v_tenant order by name limit 4) c;

  if coalesce(array_length(v_customers, 1), 0) >= 4 then
    perform better_supabase.apply_to_job(v_support, jsonb_build_object('type', 'customer', 'id', v_customers[1]), 'referral', null);
    perform better_supabase.apply_to_job(v_support, jsonb_build_object('type', 'customer', 'id', v_customers[2]), 'careers page', null);
    perform better_supabase.apply_to_job(v_sales, jsonb_build_object('type', 'customer', 'id', v_customers[3]), 'linkedin', null);
    perform better_supabase.apply_to_job(v_sales, jsonb_build_object('type', 'customer', 'id', v_customers[4]), 'careers page', null);

    v_pipeline := (better_supabase.save_pipeline(v_tenant, null, 'application', 'hiring', 'Hiring', null, true) ->> 'id')::uuid;
    perform better_supabase.save_pipeline_stage(v_pipeline, null, 'applied', 'Applied', 'active', null, null, null, null);
    perform better_supabase.save_pipeline_stage(v_pipeline, null, 'screen', 'Screen', 'active', null, null, null, null);
    perform better_supabase.save_pipeline_stage(v_pipeline, null, 'interview', 'Interview', 'active', null, null, null, null);
    perform better_supabase.save_pipeline_stage(v_pipeline, null, 'offer', 'Offer', 'active', null, null, null, null);
    perform better_supabase.save_pipeline_stage(v_pipeline, null, 'hired', 'Hired', 'hired', null, null, null, null);
    perform better_supabase.save_pipeline_stage(v_pipeline, null, 'rejected', 'Rejected', 'rejected', null, null, null, null);
    update better_supabase.applications a set pipeline_id = v_pipeline where a.tenant_id = v_tenant and a.pipeline_id is null;

    update better_supabase.applications a set stage_id = ranked.id
    from (
      select s.id, s.pipeline_id, row_number() over (partition by s.pipeline_id order by s.rank collate "C") - 1 as n
      from better_supabase.pipeline_stages s
      where s.outcome = 'open' and s.archived_at is null
    ) ranked,
    (values (v_customers[1]::text, 2), (v_customers[2]::text, 1), (v_customers[3]::text, 3)) as v_pos(candidate, n)
    where a.tenant_id = v_tenant and a.candidate_id = v_pos.candidate
      and ranked.pipeline_id = a.pipeline_id and ranked.n = v_pos.n;
  end if;

  v_course := (better_supabase.save_course(v_tenant, jsonb_build_object(
    'key', 'security-basics', 'title', 'Security basics', 'summary', 'Passwords, phishing and how to report an incident.',
    'status', 'published', 'certificate', true)) ->> 'id')::uuid;
  v_module := (better_supabase.save_course_module(v_course, jsonb_build_object('title', 'Start here')) ->> 'id')::uuid;
  perform better_supabase.save_course_lesson(v_course, jsonb_build_object(
    'moduleId', v_module, 'title', 'Spot a phishing mail', 'kind', 'content', 'required', true, 'minutes', 10));
  perform better_supabase.save_course_lesson(v_course, jsonb_build_object(
    'moduleId', v_module, 'title', 'Report an incident', 'kind', 'content', 'required', true, 'minutes', 5));
  perform better_supabase.enroll_in_course(v_course, '00000000-0000-4000-8000-0000000000a2');
  perform better_supabase.enroll_in_course(v_course, '00000000-0000-4000-8000-0000000000a1');
end
$$;

select set_config('request.jwt.claims', '', false);
