-- The credit balance accounts name `billing.read` as their read permission, so
-- RLS answers a read of their entries and the credits page no longer reads as
-- the database owner behind its own check (EX-513).
update better_supabase.ledger_accounts
set read_permission = 'billing.read'
where kind = 'credit_balance'
  and read_permission is null;
