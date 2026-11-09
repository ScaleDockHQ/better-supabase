create index if not exists "bsb_maintenance_request_material_lines_variant_idx" on "better_supabase"."maintenance_request_material_lines" ("variant_id") where "variant_id" is not null;
create index if not exists "bsb_work_item_material_lines_variant_idx" on "better_supabase"."work_item_material_lines" ("variant_id") where "variant_id" is not null;
create index if not exists invoice_open_items_document_idx on "better_supabase"."invoice_open_items" ("document_id");
create index if not exists asset_meter_readings_asset_idx on "better_supabase".asset_meter_readings ("asset_id");
create index if not exists asset_due_checks_asset_idx on "better_supabase".asset_due_checks ("asset_id");
create index if not exists asset_identifiers_asset_idx on "better_supabase".asset_identifiers ("asset_id");
