-- `gen` now skips an entity page index that the table already has. Three page indexes written
-- before that equal an index a block or the fixture declares, so drop the copies; the original
-- indexes serve the same sorts.
drop index if exists "better_supabase"."periods_tenant_id_starts_on_id_page_idx";
drop index if exists "better_supabase"."work_orders_tenant_id_created_at_id_page_idx";
drop index if exists "public"."customers_organization_id_created_at_id_page_idx";
