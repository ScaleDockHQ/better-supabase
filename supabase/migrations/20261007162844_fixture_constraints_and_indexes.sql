DROP POLICY "bs_customer_logos_delete" ON "storage"."objects";

DROP POLICY "bs_customer_logos_insert" ON "storage"."objects";

DROP POLICY "bs_customer_logos_select" ON "storage"."objects";

DROP POLICY "bs_customer_logos_update" ON "storage"."objects";

DROP INDEX "public"."contacts_organization_id_idx";

DROP INDEX "public"."customers_organization_id_status_idx";

DROP INDEX "public"."locations_organization_id_idx";

DROP INDEX "public"."notifications_user_id_idx";

ALTER TABLE "public"."customers"
  ADD CONSTRAINT "customers_archived_check" CHECK (((status <> 'archived'::text) OR (archived_at IS NOT NULL)));

CREATE INDEX contacts_organization_id_created_at_idx ON public.contacts USING btree (organization_id, created_at DESC);

CREATE INDEX customers_organization_id_status_name_idx ON public.customers USING btree (organization_id, status, name);

CREATE UNIQUE INDEX locations_one_primary_idx ON public.locations USING btree (customer_id)
  WHERE is_primary;

CREATE INDEX locations_organization_id_created_at_idx ON public.locations USING btree (organization_id, created_at DESC);

CREATE INDEX notifications_user_id_created_at_idx ON public.notifications USING btree (user_id, created_at DESC);

CREATE POLICY "bs_customer_logos_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->>
    'tenant_id'::text)))));

CREATE POLICY "bs_customer_logos_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))
    AND (name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$'::text)));

CREATE POLICY "bs_customer_logos_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->>
    'tenant_id'::text)))));

CREATE POLICY "bs_customer_logos_update" ON "storage"."objects"
  FOR UPDATE
  TO "authenticated"
  USING
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->>
    'tenant_id'::text)))))
  WITH
    CHECK
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))
    AND (name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$'::text)));

ALTER TABLE "public"."customers"
  ALTER COLUMN "created_by" SET DEFAULT auth.uid();
