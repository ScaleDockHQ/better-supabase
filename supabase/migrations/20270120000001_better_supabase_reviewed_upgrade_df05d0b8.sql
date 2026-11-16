-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- ledger: version 1 to 2. ledger_entries gets effective_at, copied from the transaction, so entries posted before the column keep their transaction's time.
alter table "better_supabase"."ledger_entries" add column if not exists "effective_at" timestamptz not null default now();
update "better_supabase"."ledger_entries" e set "effective_at" = t."effective_at"
from "better_supabase"."ledger_transactions" t
where t."id" = e."transaction_id" and e."effective_at" is distinct from t."effective_at";
