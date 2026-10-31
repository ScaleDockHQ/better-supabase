-- Registered entities, field packs and per-entity values of custom-fields
-- against the seed (ADR 0155). A definition names a registered subject type, a
-- pack installs idempotently by (pack, key), a pack never takes over a field it
-- doesn't own, and a value for one legal entity wins over the organization's
-- value for that entity only. Run with `supabase test db`.
begin;
select plan(15);

select has_column('better_supabase', 'field_definitions', 'pack', 'definitions record the pack they came from');
select has_column('better_supabase', 'field_values', 'legal_entity_id', 'values carry the optional legal entity');
select has_function('better_supabase', 'install_field_pack', array['uuid', 'jsonb'], 'install_field_pack exists');
select has_function('better_supabase', 'import_field_value', array['uuid', 'jsonb', 'text'], 'the field_value import target exists');

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

select throws_ok(
  $$select better_supabase.save_field_definition('00000000-0000-4000-8000-000000000001', 'not_a_subject', 'x', 'X', 'text', false)$$,
  '22023',
  'the entity is not a registered subject type',
  'a definition for an unregistered entity fails with FIELD_ENTITY_UNKNOWN'
);

select is(
  (select better_supabase.install_field_pack('00000000-0000-4000-8000-000000000001', $json$
    { "apiVersion": 1, "key": "neutral", "version": 1,
      "subjects": { "customer": [
        { "key": "tier", "label": "Tier", "type": "text" },
        { "key": "credit_limit", "label": "Credit limit", "type": "number", "required": true }
      ] } }
  $json$::jsonb) - 'pack'),
  '{"version": 1, "created": 2, "updated": 0, "unchanged": 0}'::jsonb,
  'the first install creates both definitions'
);
select is(
  (select better_supabase.install_field_pack('00000000-0000-4000-8000-000000000001', $json$
    { "apiVersion": 1, "key": "neutral", "version": 1,
      "subjects": { "customer": [
        { "key": "tier", "label": "Tier", "type": "text" },
        { "key": "credit_limit", "label": "Credit limit", "type": "number", "required": true }
      ] } }
  $json$::jsonb) - 'pack'),
  '{"version": 1, "created": 0, "updated": 0, "unchanged": 2}'::jsonb,
  'installing the same pack again changes nothing'
);
select is(
  (select count(*) from better_supabase.field_definitions
   where tenant_id = '00000000-0000-4000-8000-000000000001' and pack = 'neutral'),
  2::bigint,
  'the pack left two definitions, not four'
);
select is(
  (select better_supabase.install_field_pack('00000000-0000-4000-8000-000000000001', $json$
    { "apiVersion": 1, "key": "neutral", "version": 2,
      "subjects": { "customer": [
        { "key": "tier", "label": "Customer tier", "type": "text" },
        { "key": "credit_limit", "label": "Credit limit", "type": "number", "required": true }
      ] } }
  $json$::jsonb) - 'pack'),
  '{"version": 2, "created": 0, "updated": 2, "unchanged": 0}'::jsonb,
  'a new pack version updates the definitions in place'
);
select is(
  (select label from better_supabase.field_definitions
   where tenant_id = '00000000-0000-4000-8000-000000000001' and entity = 'customer' and key = 'tier'),
  'Customer tier',
  'the label follows the pack'
);

select better_supabase.save_field_definition('00000000-0000-4000-8000-000000000001', 'person', 'nickname', 'Nickname', 'text', false);
select throws_ok(
  $$select better_supabase.install_field_pack('00000000-0000-4000-8000-000000000001',
    '{"apiVersion": 1, "key": "other", "version": 1, "subjects": {"person": [{"key": "nickname", "label": "Nick", "type": "text"}]}}'::jsonb)$$,
  '23505',
  'the field already exists and doesn''t belong to this pack',
  'a pack can''t take over a field it doesn''t own'
);
select throws_ok(
  $$select better_supabase.install_field_pack('00000000-0000-4000-8000-000000000001',
    '{"apiVersion": 1, "key": "other", "version": 1, "subjects": {"nope": [{"key": "a", "label": "A", "type": "text"}]}}'::jsonb)$$,
  '22023',
  'the entity is not a registered subject type',
  'a pack for an unregistered subject type fails'
);
select throws_ok(
  $$select better_supabase.install_field_pack('00000000-0000-4000-8000-000000000001',
    '{"apiVersion": 2, "key": "other", "version": 1, "subjects": {}}'::jsonb)$$,
  '22023',
  'a field pack is an object with apiVersion 1',
  'only apiVersion 1 installs'
);

-- Per-entity resolution: the entity's value wins for that entity, the
-- organization's value stays for everyone else.
create temporary table ids (name text primary key, id uuid);
insert into ids values ('nl', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'FP01', 'Pack B.V.') ->> 'id')::uuid);
insert into ids values ('de', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'FP02', 'Pack GmbH') ->> 'id')::uuid);

insert into better_supabase.field_values (tenant_id, definition_id, subject_type, subject_id, value_text, legal_entity_id)
select '00000000-0000-4000-8000-000000000001', d.id, 'customer', 'c1', v.val, v.ent
from better_supabase.field_definitions d,
  (values ('gold', null::uuid), ('platinum', (select id from ids where name = 'nl'))) v(val, ent)
where d.tenant_id = '00000000-0000-4000-8000-000000000001' and d.entity = 'customer' and d.key = 'tier';

select is(
  (select r ->> 'text' from jsonb_array_elements(better_supabase.read_field_values(
    '00000000-0000-4000-8000-000000000001', 'customer', 'c1', (select id from ids where name = 'nl'))) r),
  'platinum',
  'the legal entity''s own value wins'
);
select is(
  (select r ->> 'text' from jsonb_array_elements(better_supabase.read_field_values(
    '00000000-0000-4000-8000-000000000001', 'customer', 'c1', (select id from ids where name = 'de'))) r),
  'gold',
  'an entity without its own value falls back to the organization''s'
);

select * from finish();
rollback;
