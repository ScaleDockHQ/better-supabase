-- knowledge_search returns chunk_id and organization_id and takes
-- priority_order. Run with `supabase test db`.
begin;
select plan(3);

select has_function(
  'better_supabase', 'knowledge_search',
  array['uuid', 'extensions.vector', 'text', 'jsonb', 'integer', 'jsonb', 'uuid[]', 'boolean'],
  'knowledge_search takes priority_order'
);
select hasnt_function(
  'better_supabase', 'knowledge_search',
  array['uuid', 'extensions.vector', 'text', 'jsonb', 'integer', 'jsonb', 'uuid[]'],
  'the earlier signature is gone'
);

insert into better_supabase.knowledge_documents (id, tenant_id, scope, scope_id, title, status)
values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-000000000001', 'organization',
  null, 'Refunds', 'ready');
insert into better_supabase.knowledge_chunks (document_id, idx, content)
values ('00000000-0000-4000-8000-0000000000d1', 0, 'refunds are paid in five days');

select is(
  (better_supabase.knowledge_search(
    '00000000-0000-4000-8000-000000000001', null, 'refunds', null, 8, null, null, false) -> 0) - 'score' - 'metadata',
  '{"idx":0,"title":"Refunds","content":"refunds are paid in five days","chunk_id":"00000000-0000-4000-8000-0000000000d1#0","document_id":"00000000-0000-4000-8000-0000000000d1","organization_id":"00000000-0000-4000-8000-000000000001"}'::jsonb,
  'a hit carries the chunk id and the organization id'
);

select * from finish();
rollback;
