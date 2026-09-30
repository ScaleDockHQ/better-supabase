-- Fixture schema for tests, examples and codegen. It exercises every feature
-- better-supabase generates types for: enums, CHECK unions, jsonb, composite
-- keys, forward and reverse relations, soft delete, timestamps and RLS.

create extension if not exists vector with schema extensions;
