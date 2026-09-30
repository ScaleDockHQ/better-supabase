create extension if not exists "vector" with schema "extensions";

create schema if not exists "better_supabase";

create schema if not exists "rbac";

create type "public"."note_kind" as enum ('call', 'meeting', 'email');

create type "rbac"."app_permission" as enum ('customers.read', 'customers.write', 'reports.read', 'users.manage', 'billing.manage', 'audit.read', 'settings.manage');

create type "rbac"."app_role" as enum ('admin', 'member');


  create table "public"."contacts" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "email" text not null,
    "full_name" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."contacts" enable row level security;


  create table "public"."customer_tags" (
    "customer_id" uuid not null,
    "tag_id" uuid not null,
    "organization_id" uuid not null
      );


alter table "public"."customer_tags" enable row level security;


  create table "public"."customers" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "kvk" text,
    "status" text not null default 'lead'::text,
    "primary_contact_id" uuid,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_by" uuid,
    "updated_by" uuid,
    "archived_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "logo_path" text
      );


alter table "public"."customers" enable row level security;


  create table "public"."locations" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "customer_id" uuid not null,
    "label" text not null,
    "city" text,
    "is_primary" boolean not null default false,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."locations" enable row level security;


  create table "public"."notes" (
    "id" bigint generated always as identity not null,
    "organization_id" uuid not null,
    "customer_id" uuid not null,
    "kind" public.note_kind not null default 'call'::public.note_kind,
    "body" text not null,
    "attachments" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "embedding" extensions.vector(3)
      );


alter table "public"."notes" enable row level security;


  create table "public"."notifications" (
    "id" bigint generated always as identity not null,
    "organization_id" uuid not null,
    "user_id" uuid not null default auth.uid(),
    "title" text not null,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."notifications" enable row level security;


  create table "public"."organizations" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "slug" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."organizations" enable row level security;


  create table "public"."tags" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "color" text not null default 'gray'::text
      );


alter table "public"."tags" enable row level security;


  create table "rbac"."role_permissions" (
    "role" rbac.app_role not null,
    "permission" rbac.app_permission not null
      );


alter table "rbac"."role_permissions" enable row level security;


  create table "rbac"."user_roles" (
    "user_id" uuid not null,
    "role" rbac.app_role not null
      );


alter table "rbac"."user_roles" enable row level security;

CREATE INDEX contacts_organization_id_idx ON public.contacts USING btree (organization_id);

CREATE UNIQUE INDEX contacts_pkey ON public.contacts USING btree (id);

CREATE INDEX customer_tags_organization_id_idx ON public.customer_tags USING btree (organization_id);

CREATE UNIQUE INDEX customer_tags_pkey ON public.customer_tags USING btree (customer_id, tag_id);

CREATE INDEX customer_tags_tag_id_idx ON public.customer_tags USING btree (tag_id);

CREATE INDEX customers_organization_id_idx ON public.customers USING btree (organization_id);

CREATE UNIQUE INDEX customers_organization_id_kvk_key ON public.customers USING btree (organization_id, kvk);

CREATE UNIQUE INDEX customers_pkey ON public.customers USING btree (id);

CREATE INDEX customers_primary_contact_id_idx ON public.customers USING btree (primary_contact_id);

CREATE INDEX locations_customer_id_idx ON public.locations USING btree (customer_id);

CREATE INDEX locations_organization_id_idx ON public.locations USING btree (organization_id);

CREATE UNIQUE INDEX locations_pkey ON public.locations USING btree (id);

CREATE INDEX notes_customer_id_idx ON public.notes USING btree (customer_id);

CREATE INDEX notes_embedding_idx ON public.notes USING hnsw (embedding extensions.vector_cosine_ops);

CREATE INDEX notes_organization_id_idx ON public.notes USING btree (organization_id);

CREATE UNIQUE INDEX notes_pkey ON public.notes USING btree (id);

CREATE INDEX notifications_organization_id_idx ON public.notifications USING btree (organization_id);

CREATE UNIQUE INDEX notifications_pkey ON public.notifications USING btree (id);

CREATE INDEX notifications_unread_idx ON public.notifications USING btree (user_id, created_at DESC) WHERE (read_at IS NULL);

CREATE UNIQUE INDEX organizations_pkey ON public.organizations USING btree (id);

CREATE UNIQUE INDEX organizations_slug_key ON public.organizations USING btree (slug);

CREATE INDEX tags_organization_id_idx ON public.tags USING btree (organization_id);

CREATE UNIQUE INDEX tags_organization_id_name_key ON public.tags USING btree (organization_id, name);

CREATE UNIQUE INDEX tags_pkey ON public.tags USING btree (id);

CREATE UNIQUE INDEX role_permissions_pkey ON rbac.role_permissions USING btree (role, permission);

CREATE UNIQUE INDEX user_roles_pkey ON rbac.user_roles USING btree (user_id);

alter table "public"."contacts" add constraint "contacts_pkey" PRIMARY KEY using index "contacts_pkey";

alter table "public"."customer_tags" add constraint "customer_tags_pkey" PRIMARY KEY using index "customer_tags_pkey";

alter table "public"."customers" add constraint "customers_pkey" PRIMARY KEY using index "customers_pkey";

alter table "public"."locations" add constraint "locations_pkey" PRIMARY KEY using index "locations_pkey";

alter table "public"."notes" add constraint "notes_pkey" PRIMARY KEY using index "notes_pkey";

alter table "public"."notifications" add constraint "notifications_pkey" PRIMARY KEY using index "notifications_pkey";

alter table "public"."organizations" add constraint "organizations_pkey" PRIMARY KEY using index "organizations_pkey";

alter table "public"."tags" add constraint "tags_pkey" PRIMARY KEY using index "tags_pkey";

alter table "rbac"."role_permissions" add constraint "role_permissions_pkey" PRIMARY KEY using index "role_permissions_pkey";

alter table "rbac"."user_roles" add constraint "user_roles_pkey" PRIMARY KEY using index "user_roles_pkey";

alter table "public"."contacts" add constraint "contacts_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."contacts" validate constraint "contacts_organization_id_fkey";

alter table "public"."customer_tags" add constraint "customer_tags_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE not valid;

alter table "public"."customer_tags" validate constraint "customer_tags_customer_id_fkey";

alter table "public"."customer_tags" add constraint "customer_tags_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."customer_tags" validate constraint "customer_tags_organization_id_fkey";

alter table "public"."customer_tags" add constraint "customer_tags_tag_id_fkey" FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE not valid;

alter table "public"."customer_tags" validate constraint "customer_tags_tag_id_fkey";

alter table "public"."customers" add constraint "customers_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."customers" validate constraint "customers_organization_id_fkey";

alter table "public"."customers" add constraint "customers_organization_id_kvk_key" UNIQUE using index "customers_organization_id_kvk_key";

alter table "public"."customers" add constraint "customers_primary_contact_id_fkey" FOREIGN KEY (primary_contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL not valid;

alter table "public"."customers" validate constraint "customers_primary_contact_id_fkey";

alter table "public"."customers" add constraint "customers_status_check" CHECK ((status = ANY (ARRAY['lead'::text, 'active'::text, 'archived'::text]))) not valid;

alter table "public"."customers" validate constraint "customers_status_check";

alter table "public"."locations" add constraint "locations_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE not valid;

alter table "public"."locations" validate constraint "locations_customer_id_fkey";

alter table "public"."locations" add constraint "locations_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."locations" validate constraint "locations_organization_id_fkey";

alter table "public"."notes" add constraint "notes_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE not valid;

alter table "public"."notes" validate constraint "notes_customer_id_fkey";

alter table "public"."notes" add constraint "notes_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."notes" validate constraint "notes_organization_id_fkey";

alter table "public"."notifications" add constraint "notifications_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."notifications" validate constraint "notifications_organization_id_fkey";

alter table "public"."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."notifications" validate constraint "notifications_user_id_fkey";

alter table "public"."organizations" add constraint "organizations_slug_key" UNIQUE using index "organizations_slug_key";

alter table "public"."tags" add constraint "tags_color_check" CHECK ((color = ANY (ARRAY['gray'::text, 'red'::text, 'green'::text, 'blue'::text]))) not valid;

alter table "public"."tags" validate constraint "tags_color_check";

alter table "public"."tags" add constraint "tags_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."tags" validate constraint "tags_organization_id_fkey";

alter table "public"."tags" add constraint "tags_organization_id_name_key" UNIQUE using index "tags_organization_id_name_key";

alter table "rbac"."user_roles" add constraint "user_roles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "rbac"."user_roles" validate constraint "user_roles_user_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  base text := 'bs:t:' || tg_table_schema || '.' || tg_table_name;
  payload jsonb := jsonb_build_object('schema', tg_table_schema, 'table', tg_table_name, 'operation', tg_op);
  source text;
  tenant text;
begin
  if tg_nargs = 0 or tg_argv[0] = '' then
    perform realtime.send(payload, 'change', base, true);
    return null;
  end if;
  source := case tg_op
    when 'INSERT' then format('select %1$I from new_rows', tg_argv[0])
    when 'DELETE' then format('select %1$I from old_rows', tg_argv[0])
    else format('select %1$I from new_rows union select %1$I from old_rows', tg_argv[0])
  end;
  for tenant in execute format('select distinct t.v::text from (%s) as t(v) where t.v is not null', source) loop
    perform realtime.send(payload, 'change', base || ':' || tenant, true);
  end loop;
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION better_supabase.current_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '')::uuid
$function$
;

CREATE OR REPLACE FUNCTION better_supabase.track_realtime(target regclass, tenant_column text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tenant_column is not null and not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = tenant_column and a.attnum > 0 and not a.attisdropped
  ) then
    tenant_column := null;
  end if;
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
  if tenant_column is null then
    execute format(
      'create trigger bs_realtime after insert or update or delete on %s for each statement execute function better_supabase.broadcast_changes()',
      target
    );
    return;
  end if;
  execute format(
    'create trigger bs_realtime_insert after insert on %s referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
  execute format(
    'create trigger bs_realtime_update after update on %s referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
  execute format(
    'create trigger bs_realtime_delete after delete on %s referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION better_supabase.untrack_realtime(target regclass)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.rs_workspace_summary(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."customers" as t0)),
    'active', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."customers" as t0 where t0."status" = 'active')),
    'mine', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."customers" as t0 where t0."created_by" = ((p->>'userId')::uuid))),
    'latestNote', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('body', t0."body", 'createdAt', t0."created_at") as row from "public"."notes" as t0 order by t0."created_at" desc limit 1) s), 'count', null)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.search_notes(query extensions.vector, k integer DEFAULT 10)
 RETURNS SETOF public.notes
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET "hnsw.iterative_scan" TO 'strict_order'
AS $function$
  select t.* from "public"."notes" t
  where t."embedding" is not null
  order by t."embedding" operator(extensions.<=>) query
  limit least(greatest(k, 1), 1000)
$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION rbac.authorize(requested_permission rbac.app_permission)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from rbac.role_permissions rp
    where rp.permission = requested_permission
      and rp.role::text = coalesce(
        auth.jwt() ->> 'user_role',
        auth.jwt() -> 'app_metadata' ->> 'user_role'
      )
  )
$function$
;

CREATE OR REPLACE FUNCTION rbac.custom_access_token_hook(event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  claims jsonb := event -> 'claims';
  user_role rbac.app_role;
begin
  select ur.role into user_role
  from rbac.user_roles ur
  where ur.user_id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
  end if;

  return jsonb_set(event, '{claims}', claims);
end;
$function$
;

grant delete on table "public"."contacts" to "authenticated";

grant insert on table "public"."contacts" to "authenticated";

grant select on table "public"."contacts" to "authenticated";

grant update on table "public"."contacts" to "authenticated";

grant delete on table "public"."contacts" to "service_role";

grant insert on table "public"."contacts" to "service_role";

grant references on table "public"."contacts" to "service_role";

grant select on table "public"."contacts" to "service_role";

grant trigger on table "public"."contacts" to "service_role";

grant truncate on table "public"."contacts" to "service_role";

grant update on table "public"."contacts" to "service_role";

grant delete on table "public"."customer_tags" to "authenticated";

grant insert on table "public"."customer_tags" to "authenticated";

grant select on table "public"."customer_tags" to "authenticated";

grant update on table "public"."customer_tags" to "authenticated";

grant delete on table "public"."customer_tags" to "service_role";

grant insert on table "public"."customer_tags" to "service_role";

grant references on table "public"."customer_tags" to "service_role";

grant select on table "public"."customer_tags" to "service_role";

grant trigger on table "public"."customer_tags" to "service_role";

grant truncate on table "public"."customer_tags" to "service_role";

grant update on table "public"."customer_tags" to "service_role";

grant delete on table "public"."customers" to "authenticated";

grant insert on table "public"."customers" to "authenticated";

grant select on table "public"."customers" to "authenticated";

grant update on table "public"."customers" to "authenticated";

grant delete on table "public"."customers" to "service_role";

grant insert on table "public"."customers" to "service_role";

grant references on table "public"."customers" to "service_role";

grant select on table "public"."customers" to "service_role";

grant trigger on table "public"."customers" to "service_role";

grant truncate on table "public"."customers" to "service_role";

grant update on table "public"."customers" to "service_role";

grant delete on table "public"."locations" to "authenticated";

grant insert on table "public"."locations" to "authenticated";

grant select on table "public"."locations" to "authenticated";

grant update on table "public"."locations" to "authenticated";

grant delete on table "public"."locations" to "service_role";

grant insert on table "public"."locations" to "service_role";

grant references on table "public"."locations" to "service_role";

grant select on table "public"."locations" to "service_role";

grant trigger on table "public"."locations" to "service_role";

grant truncate on table "public"."locations" to "service_role";

grant update on table "public"."locations" to "service_role";

grant delete on table "public"."notes" to "authenticated";

grant insert on table "public"."notes" to "authenticated";

grant select on table "public"."notes" to "authenticated";

grant update on table "public"."notes" to "authenticated";

grant delete on table "public"."notes" to "service_role";

grant insert on table "public"."notes" to "service_role";

grant references on table "public"."notes" to "service_role";

grant select on table "public"."notes" to "service_role";

grant trigger on table "public"."notes" to "service_role";

grant truncate on table "public"."notes" to "service_role";

grant update on table "public"."notes" to "service_role";

grant delete on table "public"."notifications" to "anon";

grant insert on table "public"."notifications" to "anon";

grant references on table "public"."notifications" to "anon";

grant select on table "public"."notifications" to "anon";

grant trigger on table "public"."notifications" to "anon";

grant truncate on table "public"."notifications" to "anon";

grant update on table "public"."notifications" to "anon";

grant delete on table "public"."notifications" to "authenticated";

grant insert on table "public"."notifications" to "authenticated";

grant references on table "public"."notifications" to "authenticated";

grant select on table "public"."notifications" to "authenticated";

grant trigger on table "public"."notifications" to "authenticated";

grant truncate on table "public"."notifications" to "authenticated";

grant update on table "public"."notifications" to "authenticated";

grant delete on table "public"."notifications" to "service_role";

grant insert on table "public"."notifications" to "service_role";

grant references on table "public"."notifications" to "service_role";

grant select on table "public"."notifications" to "service_role";

grant trigger on table "public"."notifications" to "service_role";

grant truncate on table "public"."notifications" to "service_role";

grant update on table "public"."notifications" to "service_role";

grant select on table "public"."organizations" to "authenticated";

grant delete on table "public"."organizations" to "service_role";

grant insert on table "public"."organizations" to "service_role";

grant references on table "public"."organizations" to "service_role";

grant select on table "public"."organizations" to "service_role";

grant trigger on table "public"."organizations" to "service_role";

grant truncate on table "public"."organizations" to "service_role";

grant update on table "public"."organizations" to "service_role";

grant delete on table "public"."tags" to "authenticated";

grant insert on table "public"."tags" to "authenticated";

grant select on table "public"."tags" to "authenticated";

grant update on table "public"."tags" to "authenticated";

grant delete on table "public"."tags" to "service_role";

grant insert on table "public"."tags" to "service_role";

grant references on table "public"."tags" to "service_role";

grant select on table "public"."tags" to "service_role";

grant trigger on table "public"."tags" to "service_role";

grant truncate on table "public"."tags" to "service_role";

grant update on table "public"."tags" to "service_role";

grant select on table "rbac"."user_roles" to "supabase_auth_admin";


  create policy "contacts_tenant"
  on "public"."contacts"
  as permissive
  for all
  to authenticated
using ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)))
with check ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "customer_tags_tenant"
  on "public"."customer_tags"
  as permissive
  for all
  to authenticated
using ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)))
with check ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "customers_tenant"
  on "public"."customers"
  as permissive
  for all
  to authenticated
using ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)))
with check ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "locations_tenant"
  on "public"."locations"
  as permissive
  for all
  to authenticated
using ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)))
with check ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "notes_tenant"
  on "public"."notes"
  as permissive
  for all
  to authenticated
using ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)))
with check ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "notifications_own"
  on "public"."notifications"
  as permissive
  for all
  to authenticated
using (((user_id = ( SELECT auth.uid() AS uid)) AND (organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id))))
with check (((user_id = ( SELECT auth.uid() AS uid)) AND (organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id))));



  create policy "organizations_member_select"
  on "public"."organizations"
  as permissive
  for select
  to authenticated
using ((id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "tags_tenant"
  on "public"."tags"
  as permissive
  for all
  to authenticated
using ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)))
with check ((organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)));



  create policy "Auth admin reads user roles"
  on "rbac"."user_roles"
  as permissive
  for select
  to supabase_auth_admin
using (true);


CREATE TRIGGER contacts_set_updated_at BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER customers_set_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER locations_set_updated_at BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER notes_set_updated_at BEFORE UPDATE ON public.notes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER bs_realtime_delete AFTER DELETE ON public.notifications REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes('organization_id');

CREATE TRIGGER bs_realtime_insert AFTER INSERT ON public.notifications REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes('organization_id');

CREATE TRIGGER bs_realtime_update AFTER UPDATE ON public.notifications REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.broadcast_changes('organization_id');

CREATE TRIGGER organizations_set_updated_at BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


  create policy "bs_realtime_tables_receive"
  on "realtime"."messages"
  as permissive
  for select
  to authenticated
using (((extension = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'bs:t:%'::text) AND ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = ''::text) OR (split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text), ''::text)))));



  create policy "bs_customer_logos_delete"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'customer-logos'::text) AND (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))));



  create policy "bs_customer_logos_insert"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'customer-logos'::text) AND (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text))) AND (name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$'::text)));



  create policy "bs_customer_logos_select"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'customer-logos'::text) AND (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))));



  create policy "bs_customer_logos_update"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((bucket_id = 'customer-logos'::text) AND (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))))
with check (((bucket_id = 'customer-logos'::text) AND (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text))) AND (name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$'::text)));



-- Reviewed additions. `supabase db diff` generated everything above from
-- supabase/schemas; it does not track revokes, schema or function privileges,
-- data or role settings, so those follow by hand.

grant usage on schema better_supabase to anon, authenticated, service_role;

revoke all on
  public.organizations,
  public.contacts,
  public.customers,
  public.locations,
  public.tags,
  public.customer_tags,
  public.notes
from anon, authenticated;
grant select on public.organizations to authenticated;
grant select, insert, update, delete on
  public.contacts,
  public.customers,
  public.locations,
  public.tags,
  public.customer_tags,
  public.notes,
  public.notifications
to authenticated;
grant all on all tables in schema public to service_role;

grant usage on schema rbac to supabase_auth_admin, authenticated;
grant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function rbac.custom_access_token_hook(jsonb) from authenticated, anon, public;
grant select on rbac.user_roles to supabase_auth_admin;
revoke all on rbac.user_roles from authenticated, anon, public;
grant execute on function rbac.authorize(rbac.app_permission) to authenticated;

revoke execute on function public.rs_workspace_summary(jsonb) from public, anon, authenticated;
grant execute on function public.rs_workspace_summary(jsonb) to authenticated;

revoke execute on function "public"."search_notes"(extensions.vector, integer) from public, anon;
grant execute on function "public"."search_notes"(extensions.vector, integer) to authenticated, service_role;

revoke execute on function better_supabase.track_realtime(regclass, text) from public, anon, authenticated;
revoke execute on function better_supabase.untrack_realtime(regclass) from public, anon, authenticated;

insert into rbac.role_permissions (role, permission)
select 'admin', permission
from unnest(enum_range(null::rbac.app_permission)) as permission;

insert into rbac.role_permissions (role, permission) values
  ('member', 'customers.read');

-- better-supabase: bucket customer-logos ({orgId}/{customerId}/logo/{version}.webp)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('customer-logos', 'customer-logos', true, 5242880, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- `aggregate()` and `_sum`/`_avg`/`_min`/`_max` includes need PostgREST
-- aggregates, which are off by default (doctor BS210).
alter role authenticator set pgrst.db_aggregates_enabled = 'true';
notify pgrst, 'reload config';
