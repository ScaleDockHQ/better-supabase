insert into public.organizations (id, name, slug) values
  ('00000000-0000-4000-8000-000000000001', 'Acme', 'acme'),
  ('00000000-0000-4000-8000-000000000002', 'Globex', 'globex');

insert into public.contacts (id, organization_id, email, full_name) values
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-000000000001', 'wile@acme.test', 'Wile E. Coyote');

insert into public.customers (id, organization_id, name, kvk, status, primary_contact_id, metadata) values
  ('00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-000000000001', 'Road Runner Inc', '1001', 'active', '00000000-0000-4000-8000-00000000c001', '{"tier":"gold","tags":["vip"]}'),
  ('00000000-0000-4000-8000-00000000a002', '00000000-0000-4000-8000-000000000001', 'Anvil Supplies', '1002', 'lead', null, '{"tier":"silver","tags":[]}'),
  ('00000000-0000-4000-8000-00000000a003', '00000000-0000-4000-8000-000000000002', 'Initech', '2001', 'active', null, '{"tier":"bronze","tags":[]}');

insert into public.tags (id, organization_id, name, color) values
  ('00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-000000000001', 'VIP', 'green');

insert into public.customer_tags (customer_id, tag_id, organization_id) values
  ('00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-000000000001');

-- Tags of the tags block, for the tag input on the customer page.
insert into better_supabase.tags (id, tenant_id, kind, name, slug, rank) values
  ('00000000-0000-4000-8000-00000000b101', '00000000-0000-4000-8000-000000000001', 'customer', 'VIP', 'vip', 'V'),
  ('00000000-0000-4000-8000-00000000b102', '00000000-0000-4000-8000-000000000001', 'customer', 'Churn risk', 'churn-risk', 'k');

insert into better_supabase.taggings (tenant_id, tag_id, subject_type, subject_id) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000b101', 'customer', '00000000-0000-4000-8000-00000000a001');

insert into public.locations (organization_id, customer_id, label, city, is_primary) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'HQ', 'Amsterdam', true);

insert into public.notes (organization_id, customer_id, kind, body, embedding) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'meeting', 'Kickoff', '[0.9,0.1,0.1]'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'email', 'Sent the invoice', '[0.1,0.2,0.9]'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'call', 'Asked when the invoice is due', '[0.2,0.2,0.9]');

-- Three local users for the Next.js example (password: `password123`). The
-- admin owns Acme and is a member of Globex; the member belongs to Acme; the
-- Globex owner belongs to Globex. `tenant_id` in app_metadata is each user's
-- active organization (switch_organization rewrites it). The admin also gets
-- a row in rbac.user_roles, so the hook adds `user_role: "admin"`.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated',
   'admin@acme.test', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"00000000-0000-4000-8000-000000000001"}', '{"full_name":"Ada Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000a2', 'authenticated', 'authenticated',
   'member@acme.test', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"00000000-0000-4000-8000-000000000001"}', '{"full_name":"Max Member"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000a3', 'authenticated', 'authenticated',
   'owner@globex.test', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"00000000-0000-4000-8000-000000000002"}', '{"full_name":"Gina Globex"}', now(), now(), '', '', '', '');

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, jsonb_build_object('sub', u.id::text, 'email', u.email), 'email', now(), now(), now()
from auth.users u
where u.id in ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a3');

insert into rbac.user_roles (user_id, role) values
  ('00000000-0000-4000-8000-0000000000a1', 'admin'),
  ('00000000-0000-4000-8000-0000000000a2', 'member');

-- Roles are rows of the permissions block's catalog; a membership points at
-- the role's id.
insert into public.memberships (organization_id, user_id, role, created_at)
select m.organization_id, m.user_id, r.id, now() - m.age
from (values
  ('00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 'owner', interval '30 days'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'member', interval '20 days'),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000a3', 'owner', interval '25 days'),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000a1', 'member', interval '10 days')
) as m(organization_id, user_id, role, age)
join better_supabase.roles r on r.key = m.role;

-- Acme's teams: Sales has both members, Support only the owner.
insert into better_supabase.teams (id, tenant_id, name, slug, description, created_by) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-000000000001', 'Sales', 'sales', 'New business and renewals.', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-000000000001', 'Support', 'support', 'Customer questions and incidents.', '00000000-0000-4000-8000-0000000000a1');

insert into better_supabase.team_members (team_id, user_id, tenant_id) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000001');

-- Plans and their features (the entitlements module's plan catalog), and
-- the quotas the usage module enforces per plan.
insert into public.plans (key, name, price_cents, position) values
  ('free', 'Free', 0, 1),
  ('pro', 'Pro', 2900, 2),
  ('enterprise', 'Enterprise', 9900, 3);

insert into public.plan_features (plan_key, feature_key, value) values
  ('free', 'seats', '3'),
  ('pro', 'seats', '20'),
  ('pro', 'exports', null),
  ('pro', 'audit', null),
  ('enterprise', 'seats', '200'),
  ('enterprise', 'exports', null),
  ('enterprise', 'audit', null),
  ('enterprise', 'sso', null);

insert into public.subscriptions (organization_id, plan_key, status, current_period_end) values
  ('00000000-0000-4000-8000-000000000001', 'pro', 'active', now() + interval '18 days'),
  ('00000000-0000-4000-8000-000000000002', 'free', 'active', null);

insert into better_supabase.usage_quotas (plan, meter, "limit", period) values
  ('free', 'api.calls', 1000, 'month'),
  ('pro', 'api.calls', 50000, 'month'),
  ('enterprise', 'api.calls', null, 'month'),
  ('free', 'customers.created', 25, 'month'),
  ('pro', 'customers.created', 1000, 'month'),
  ('enterprise', 'customers.created', null, 'month');

insert into better_supabase.usage_counters (organization_id, meter, day, value) values
  ('00000000-0000-4000-8000-000000000001', 'api.calls', current_date, 12840),
  ('00000000-0000-4000-8000-000000000001', 'customers.created', current_date, 2),
  ('00000000-0000-4000-8000-000000000002', 'api.calls', current_date, 412),
  ('00000000-0000-4000-8000-000000000002', 'customers.created', current_date, 1);

-- An open invitation to Acme. Its token is `seed-invitation-acme`
-- (/invite/seed-invitation-acme); only the SHA-256 hash is stored.
insert into better_supabase.invitations (organization_id, email, role, token_hash, invited_by, expires_at) values
  ('00000000-0000-4000-8000-000000000001', 'new@acme.test', 'member',
   encode(extensions.digest('seed-invitation-acme', 'sha256'), 'hex'),
   '00000000-0000-4000-8000-0000000000a1', now() + interval '7 days');

-- The beta page: off by default, on for Acme.
insert into better_supabase.flags (key, description, default_variant) values
  ('beta-page', 'Shows the Beta page in the sidebar', 'off');
insert into better_supabase.flag_overrides (flag_key, organization_id, variant) values
  ('beta-page', '00000000-0000-4000-8000-000000000001', 'on');

insert into better_supabase.announcements (title, body, severity, href, created_by) values
  ('Organizations are here', 'Switch between organizations from the sidebar, and invite your team.', 'info', '/settings/members',
   '00000000-0000-4000-8000-0000000000a1');

-- Acme has done the first step of its checklist.
select better_supabase.enrollment_mark(
  better_supabase.enrollment_ensure(
    '00000000-0000-4000-8000-000000000001', 'onboarding:getting-started', null,
    array['customer', 'invite', 'api-key', 'plan'], 'organization',
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1'
  ),
  'customer', true, '00000000-0000-4000-8000-0000000000a1'
);

-- A welcome notification for both Acme users, through the notifications
-- module so the recipients, deliveries and realtime pings match a real send.
select better_supabase.notify(jsonb_build_object(
  'type', 'test.sent',
  'tenant', '00000000-0000-4000-8000-000000000001',
  'actor', '00000000-0000-4000-8000-0000000000a1',
  'recipients', jsonb_build_array('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2'),
  'include_actor', true,
  'data', jsonb_build_object('title', 'Welcome to Acme'),
  'key', 'seed-welcome-acme'
));

-- The Help inbox behind the example's Help sheet and /inbox, with one
-- customer conversation waiting. Staff answer: the bot is left out.
insert into better_supabase.inboxes (id, tenant_id, name, channel, bot_mode, settings) values
  ('00000000-0000-4000-8000-00000000e001', '00000000-0000-4000-8000-000000000001', 'Help', 'in_app', 'human', '{"widget": true}');

select better_supabase.record_inbound(jsonb_build_object(
  'inbox_id', '00000000-0000-4000-8000-00000000e001',
  'thread_id', 'inbox:seed-road-runner',
  'subject', 'Wrong VAT number',
  'contact', jsonb_build_object('external_id', 'beep@roadrunner.test', 'name', 'Road Runner', 'email', 'beep@roadrunner.test'),
  'message', jsonb_build_object('body', 'Our last invoice shows the wrong VAT number. Can you fix it?')
));

-- Acme's work: two projects and eight items behind /work, numbered the way
-- create_work_item numbers them (TASK-<n> per organization). The items insert
-- runs without triggers, since the state machine would start every item in
-- triage; the closed items set closed_at and close_reason here.
insert into better_supabase.work_projects (id, tenant_id, key, name, owner_user_id, status, start_on, target_on) values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'WEB', 'Website relaunch', '00000000-0000-4000-8000-0000000000a1', 'active', current_date - 14, current_date + 30),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000001', 'ONB', 'Customer onboarding', '00000000-0000-4000-8000-0000000000a2', 'planned', current_date + 7, current_date + 60);

set session_replication_role = replica;

insert into better_supabase.work_items (id, tenant_id, number, identifier, title, body, team_id, project_id, priority, estimate, state, due_at, rank, created_by, closed_at, close_reason) values
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-000000000001', 1, 'TASK-1', 'Draft the new homepage copy', 'Hero, pricing teaser and the customer quotes.', '00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000f001', 2, 3, 'started', now() + interval '5 days', 'V', '00000000-0000-4000-8000-0000000000a1', null, null),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-000000000001', 2, 'TASK-2', 'Pick a hosting plan', null, null, '00000000-0000-4000-8000-00000000f001', 3, 1, 'completed', null, 'W', '00000000-0000-4000-8000-0000000000a1', now() - interval '3 days', 'completed'),
  ('00000000-0000-4000-8000-00000000f103', '00000000-0000-4000-8000-000000000001', 3, 'TASK-3', 'Redirect the old blog URLs', 'Map every /blog/<year>/<slug> to /posts/<slug>.', null, '00000000-0000-4000-8000-00000000f001', 2, 2, 'unstarted', now() + interval '12 days', 'X', '00000000-0000-4000-8000-0000000000a1', null, null),
  ('00000000-0000-4000-8000-00000000f104', '00000000-0000-4000-8000-000000000001', 4, 'TASK-4', 'Fix the broken contact form on mobile', null, '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-00000000f001', 1, 1, 'triage', now() + interval '2 days', 'Y', '00000000-0000-4000-8000-0000000000a2', null, null),
  ('00000000-0000-4000-8000-00000000f105', '00000000-0000-4000-8000-000000000001', 5, 'TASK-5', 'Write the welcome email series', 'Three emails over the first week.', '00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000f002', 3, 5, 'backlog', null, 'V', '00000000-0000-4000-8000-0000000000a2', null, null),
  ('00000000-0000-4000-8000-00000000f106', '00000000-0000-4000-8000-000000000001', 6, 'TASK-6', 'Record a product walkthrough', null, null, '00000000-0000-4000-8000-00000000f002', 4, 3, 'backlog', null, 'W', '00000000-0000-4000-8000-0000000000a1', null, null),
  ('00000000-0000-4000-8000-00000000f107', '00000000-0000-4000-8000-000000000001', 7, 'TASK-7', 'Answer the open VAT question', 'Road Runner reported the wrong VAT number on an invoice.', '00000000-0000-4000-8000-0000000000e2', null, 1, 1, 'started', now() + interval '1 day', 'V', '00000000-0000-4000-8000-0000000000a1', null, null),
  ('00000000-0000-4000-8000-00000000f108', '00000000-0000-4000-8000-000000000001', 8, 'TASK-8', 'Archive last year''s leads', null, '00000000-0000-4000-8000-0000000000e1', null, 0, null, 'canceled', null, 'W', '00000000-0000-4000-8000-0000000000a2', now() - interval '1 day', 'not_planned');

set session_replication_role = origin;

insert into better_supabase.work_item_assignees (tenant_id, work_item_id, user_id) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f104', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f105', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f107', '00000000-0000-4000-8000-0000000000a1');

insert into better_supabase.work_item_checklist_items (tenant_id, work_item_id, title, done, done_at, done_by, rank, created_by) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', 'Hero headline', true, now() - interval '1 day', '00000000-0000-4000-8000-0000000000a1', 'V', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', 'Pricing teaser', false, null, null, 'W', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', 'Three customer quotes', false, null, null, 'X', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f105', 'Day 1: welcome', false, null, null, 'V', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f105', 'Day 3: invite your team', false, null, null, 'W', '00000000-0000-4000-8000-0000000000a2');
