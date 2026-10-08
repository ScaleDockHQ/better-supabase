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

insert into public.memberships (organization_id, user_id, role, created_at) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'owner', now() - interval '30 days'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'member', now() - interval '20 days'),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000a3', 'owner', now() - interval '25 days'),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000a1', 'member', now() - interval '10 days');

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
insert into better_supabase.onboarding_progress (checklist, step, organization_id, completed_by) values
  ('getting-started', 'customer', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1');

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
