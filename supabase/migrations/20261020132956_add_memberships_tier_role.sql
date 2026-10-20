ALTER TABLE "public"."memberships"
  ADD COLUMN "tier_role" text GENERATED ALWAYS AS (
CASE
    WHEN (ROLE = ANY (ARRAY['owner'::text, 'admin'::text])) THEN 'manager'::text
    ELSE 'member'::text
END) STORED;
