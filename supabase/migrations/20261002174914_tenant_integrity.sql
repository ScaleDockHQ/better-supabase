create extension if not exists "pg_trgm" with schema "extensions";

revoke delete on table "public"."notifications" from "anon";

revoke insert on table "public"."notifications" from "anon";

revoke references on table "public"."notifications" from "anon";

revoke select on table "public"."notifications" from "anon";

revoke trigger on table "public"."notifications" from "anon";

revoke truncate on table "public"."notifications" from "anon";

revoke update on table "public"."notifications" from "anon";

revoke references on table "public"."notifications" from "authenticated";

revoke trigger on table "public"."notifications" from "authenticated";

revoke truncate on table "public"."notifications" from "authenticated";

alter table "public"."customer_tags" drop constraint "customer_tags_customer_id_fkey";

alter table "public"."customer_tags" drop constraint "customer_tags_tag_id_fkey";

alter table "public"."customers" drop constraint "customers_primary_contact_id_fkey";

alter table "public"."locations" drop constraint "locations_customer_id_fkey";

alter table "public"."notes" drop constraint "notes_customer_id_fkey";

drop index if exists "public"."customers_organization_id_idx";

drop index if exists "public"."tags_organization_id_idx";

drop index if exists "public"."customer_tags_tag_id_idx";

drop index if exists "public"."customers_primary_contact_id_idx";

drop index if exists "public"."locations_customer_id_idx";

drop index if exists "public"."notes_customer_id_idx";

drop index if exists "public"."notes_organization_id_idx";

CREATE UNIQUE INDEX contacts_id_organization_id_key ON public.contacts USING btree (id, organization_id);

CREATE INDEX customer_tags_customer_id_idx ON public.customer_tags USING btree (customer_id, organization_id);

CREATE INDEX customers_active_idx ON public.customers USING btree (organization_id, created_at DESC) WHERE (archived_at IS NULL);

CREATE UNIQUE INDEX customers_id_organization_id_key ON public.customers USING btree (id, organization_id);

CREATE INDEX customers_name_trgm_idx ON public.customers USING gin (name extensions.gin_trgm_ops);

CREATE INDEX customers_organization_id_created_by_idx ON public.customers USING btree (organization_id, created_by);

CREATE INDEX customers_organization_id_status_idx ON public.customers USING btree (organization_id, status);

CREATE INDEX notifications_user_id_idx ON public.notifications USING btree (user_id);

CREATE UNIQUE INDEX tags_id_organization_id_key ON public.tags USING btree (id, organization_id);

CREATE INDEX customer_tags_tag_id_idx ON public.customer_tags USING btree (tag_id, organization_id);

CREATE INDEX customers_primary_contact_id_idx ON public.customers USING btree (primary_contact_id, organization_id);

CREATE INDEX locations_customer_id_idx ON public.locations USING btree (customer_id, organization_id);

CREATE INDEX notes_customer_id_idx ON public.notes USING btree (customer_id, organization_id, created_at DESC);

CREATE INDEX notes_organization_id_idx ON public.notes USING btree (organization_id, created_at DESC);

alter table "public"."contacts" add constraint "contacts_id_organization_id_key" UNIQUE using index "contacts_id_organization_id_key";

alter table "public"."customers" add constraint "customers_id_organization_id_key" UNIQUE using index "customers_id_organization_id_key";

alter table "public"."tags" add constraint "tags_id_organization_id_key" UNIQUE using index "tags_id_organization_id_key";

alter table "public"."customer_tags" add constraint "customer_tags_customer_id_fkey" FOREIGN KEY (customer_id, organization_id) REFERENCES public.customers(id, organization_id) ON DELETE CASCADE not valid;

alter table "public"."customer_tags" validate constraint "customer_tags_customer_id_fkey";

alter table "public"."customer_tags" add constraint "customer_tags_tag_id_fkey" FOREIGN KEY (tag_id, organization_id) REFERENCES public.tags(id, organization_id) ON DELETE CASCADE not valid;

alter table "public"."customer_tags" validate constraint "customer_tags_tag_id_fkey";

alter table "public"."customers" add constraint "customers_primary_contact_id_fkey" FOREIGN KEY (primary_contact_id, organization_id) REFERENCES public.contacts(id, organization_id) ON DELETE SET NULL (primary_contact_id) not valid;

alter table "public"."customers" validate constraint "customers_primary_contact_id_fkey";

alter table "public"."locations" add constraint "locations_customer_id_fkey" FOREIGN KEY (customer_id, organization_id) REFERENCES public.customers(id, organization_id) ON DELETE CASCADE not valid;

alter table "public"."locations" validate constraint "locations_customer_id_fkey";

alter table "public"."notes" add constraint "notes_customer_id_fkey" FOREIGN KEY (customer_id, organization_id) REFERENCES public.customers(id, organization_id) ON DELETE CASCADE not valid;

alter table "public"."notes" validate constraint "notes_customer_id_fkey";

-- Added by hand: the diff does not carry function execute grants.

revoke execute on function rbac.authorize(rbac.app_permission) from public, anon;
