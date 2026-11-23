-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- invoices: version 3 to 4. invoice_open_items keeps unallocated payments and future-dated invoices, so its document_id no longer references invoices. The data migration rebuilds every organization's rows.
alter table if exists "better_supabase"."invoice_open_items" drop constraint if exists "invoice_open_items_document_id_fkey";
