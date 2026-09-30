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

-- Two local users for the Next.js example (password: `password123`). Both
-- belong to Acme; the admin gets a row in rbac.user_roles, so the custom
-- access token hook adds `user_role: "admin"` to their tokens.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated',
   'admin@acme.test', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"00000000-0000-4000-8000-000000000001"}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000a2', 'authenticated', 'authenticated',
   'member@acme.test', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"],"tenant_id":"00000000-0000-4000-8000-000000000001"}', '{}', now(), now(), '', '', '', '');

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, jsonb_build_object('sub', u.id::text, 'email', u.email), 'email', now(), now(), now()
from auth.users u
where u.id in ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2');

insert into rbac.user_roles (user_id, role) values
  ('00000000-0000-4000-8000-0000000000a1', 'admin'),
  ('00000000-0000-4000-8000-0000000000a2', 'member');
