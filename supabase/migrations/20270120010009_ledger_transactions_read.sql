ALTER POLICY "bsb_ledger_transactions_read" ON "better_supabase"."ledger_transactions"
  USING ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "better_supabase"."ledger_transactions"."id"));

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."ledger_transactions";

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."ledger_transactions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.ledger_entries y
  WHERE (y.transaction_id = ledger_transactions.id))))));
