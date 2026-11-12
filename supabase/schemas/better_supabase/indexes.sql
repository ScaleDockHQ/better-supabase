-- Keyset order of the admin lists on the biggest module table (EX-500). The id
-- expression is the cursor key of the search settings list, so a page seeks to
-- its cursor instead of sorting every document of the tenant.
create index search_documents_tenant_updated_idx
  on better_supabase.search_documents (tenant_id, updated_at desc, (subject_type || ':' || subject_id) desc);
