ALTER POLICY "bsb_ledger_transactions_read" ON "better_supabase"."ledger_transactions"
  USING ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "better_supabase"."ledger_transactions"."id"));
