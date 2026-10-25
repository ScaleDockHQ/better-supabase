ALTER TABLE "public"."organizations"
  DROP CONSTRAINT "organizations_stripe_customer_id_key";

ALTER TABLE "public"."organizations"
  DROP COLUMN "stripe_customer_id";
