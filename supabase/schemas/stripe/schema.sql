-- The Stripe Sync Engine's tables, reduced to the columns the billing block reads.
-- A deployment that syncs Stripe replaces them with the engine's own schema; here
-- they stay empty so the block's functions resolve their relations.
create schema if not exists stripe;
