ALTER TABLE "public"."customers"
  ADD CONSTRAINT "customers_name_check" CHECK (((char_length(name) >= 1) AND (char_length(name) <= 200)));

COMMENT ON COLUMN "public"."customers"."kvk" IS 'Chamber of Commerce (KvK) number.
@example "12345678"';

COMMENT ON COLUMN "public"."customers"."name" IS 'Trading name.
@example "Acme B.V."';

COMMENT ON TABLE "public"."customers" IS 'Companies the organization sells to.';
