ALTER TABLE "stripe"."tax_ids"
  ADD COLUMN "country" text,
  ADD COLUMN "verification" jsonb;
