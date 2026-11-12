CREATE INDEX search_documents_tenant_updated_idx ON better_supabase.search_documents USING btree (tenant_id, updated_at DESC, (((subject_type || ':'::text) || subject_id)) DESC);

CREATE INDEX customers_organization_id_created_at_id_idx ON public.customers USING btree (organization_id, created_at DESC, id DESC);
