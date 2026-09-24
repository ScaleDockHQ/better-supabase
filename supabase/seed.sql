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

insert into public.notes (organization_id, customer_id, kind, body) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'meeting', 'Kickoff');
