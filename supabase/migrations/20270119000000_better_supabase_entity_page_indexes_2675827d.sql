-- The indexes the entity page lists need, one per declared sort, facet and
-- searched column. Managed by `better-supabase gen` (gen.entityPages): it
-- writes a new migration when a page or its block's list surface changes.
create index if not exists "periods_tenant_id_starts_on_id_page_idx" on "better_supabase"."periods" ("tenant_id", "starts_on", "id");
create index if not exists "periods_tenant_id_ends_on_id_page_idx" on "better_supabase"."periods" ("tenant_id", "ends_on", "id");
create index if not exists "periods_tenant_id_kind_page_idx" on "better_supabase"."periods" ("tenant_id", "kind");
create index if not exists "periods_tenant_id_status_page_idx" on "better_supabase"."periods" ("tenant_id", "status");
create index if not exists "risks_tenant_id_residual_score_id_page_idx" on "better_supabase"."risks" ("tenant_id", "residual_score", "id");
create index if not exists "risks_tenant_id_number_id_page_idx" on "better_supabase"."risks" ("tenant_id", "number", "id");
create index if not exists "risks_tenant_id_next_review_on_id_page_idx" on "better_supabase"."risks" ("tenant_id", "next_review_on", "id");
create index if not exists "risks_tenant_id_status_page_idx" on "better_supabase"."risks" ("tenant_id", "status");
create index if not exists "risks_tenant_id_category_page_idx" on "better_supabase"."risks" ("tenant_id", "category");
create index if not exists "work_orders_tenant_id_created_at_id_page_idx" on "better_supabase"."work_orders" ("tenant_id", "created_at", "id");
create index if not exists "work_orders_tenant_id_starts_at_id_page_idx" on "better_supabase"."work_orders" ("tenant_id", "starts_at", "id");
create index if not exists "work_orders_tenant_id_title_id_page_idx" on "better_supabase"."work_orders" ("tenant_id", "title", "id");
create index if not exists "work_orders_tenant_id_status_page_idx" on "better_supabase"."work_orders" ("tenant_id", "status");
create index if not exists "work_orders_tenant_id_priority_page_idx" on "better_supabase"."work_orders" ("tenant_id", "priority");
create index if not exists "commissions_tenant_id_occurred_on_id_page_idx" on "better_supabase"."commissions" ("tenant_id", "occurred_on", "id");
create index if not exists "commissions_tenant_id_created_at_id_page_idx" on "better_supabase"."commissions" ("tenant_id", "created_at", "id");
create index if not exists "commissions_tenant_id_amount_id_page_idx" on "better_supabase"."commissions" ("tenant_id", "amount", "id");
create index if not exists "commissions_tenant_id_status_page_idx" on "better_supabase"."commissions" ("tenant_id", "status");
create index if not exists "commissions_tenant_id_seller_id_page_idx" on "better_supabase"."commissions" ("tenant_id", "seller_id");
create index if not exists "referrals_tenant_id_created_at_id_page_idx" on "better_supabase"."referrals" ("tenant_id", "created_at", "id");
create index if not exists "referrals_tenant_id_status_page_idx" on "better_supabase"."referrals" ("tenant_id", "status");
create index if not exists "referrals_tenant_id_referrer_id_page_idx" on "better_supabase"."referrals" ("tenant_id", "referrer_id");
