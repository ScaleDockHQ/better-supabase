-- Both Phase 8 chains indexed the ledger hold foreign keys. Chain B
-- (20261022015314_ledger_hold_indexes) dropped ledger_holds_account_idx and
-- created ledger_holds_account_status_idx and ledger_holds_transaction_idx;
-- chain A (20261022031636_index_foreign_keys) drops ledger_holds_account_idx
-- again and creates both indexes under its own names. Neither pushed migration
-- can change, so this one restores the state chain A's migration expects.

DROP INDEX IF EXISTS "better_supabase"."ledger_holds_account_status_idx";

DROP INDEX IF EXISTS "better_supabase"."ledger_holds_transaction_idx";

CREATE INDEX IF NOT EXISTS ledger_holds_account_idx ON better_supabase.ledger_holds USING btree (account_id)
  WHERE (status = 'active'::text);
