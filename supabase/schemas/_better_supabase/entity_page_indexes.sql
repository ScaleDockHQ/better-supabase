-- The indexes the entity page lists need, one per declared sort, facet and
-- searched column. Managed by `better-supabase gen` (gen.entityPages): it
-- writes a new migration when a page or its block's list surface changes.
create index "periods_tenant_id_starts_on_id_page_idx" on "better_supabase"."periods" ("tenant_id", "starts_on", "id");
create index "periods_tenant_id_ends_on_id_page_idx" on "better_supabase"."periods" ("tenant_id", "ends_on", "id");
create index "periods_tenant_id_kind_page_idx" on "better_supabase"."periods" ("tenant_id", "kind");
create index "periods_tenant_id_status_page_idx" on "better_supabase"."periods" ("tenant_id", "status");
