SET local check_function_bodies = off;

ALTER TABLE "public"."customers"
  ADD COLUMN "owner_team_id" uuid;

CREATE OR REPLACE FUNCTION better_supabase.list_teams (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t."id",
    'name', t."name",
    'slug', t."slug",
    'description', t."description",
    'status', t."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb)
  ) order by t."name"), '[]'::jsonb)
  from "better_supabase"."teams" t
  where t."tenant_id" = list_teams.tenant
    and (
      auth.role() = 'service_role'
      or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_team (
  team        uuid,
  name        text,
  description text,
  patch       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if update_team.patch is not null and (jsonb_typeof(update_team.patch) <> 'object'
    or update_team.patch ? 'slug' and coalesce(update_team.patch ->> 'slug', '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    or update_team.patch ? 'name' and nullif(trim(update_team.patch ->> 'name'), '') is null) then
    raise exception 'patch sets name, slug or description; name and slug can''t be empty' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.patch ->> 'name', update_team.name, t."name"),
      "slug" = case when update_team.patch ? 'slug' then update_team.patch ->> 'slug' else t."slug" end,
      "description" = case when update_team.patch ? 'description' then update_team.patch ->> 'description' else coalesce(update_team.description, t."description") end,
      "updated_at" = now()
  where t."id" = update_team.team;
  perform "better_supabase".emit_event('team.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name), 'teams/' || (update_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$function$;

CREATE OR REPLACE FUNCTION public.customers_owner_team_check()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not exists (
    select 1
    from better_supabase.teams t
    where t.id = new.owner_team_id
      and t.tenant_id = new.organization_id
  ) then
    raise exception 'owner team belongs to another organization'
      using errcode = '23503', hint = 'CUSTOMER_OWNER_TEAM';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."customers_owner_team_check"() FROM PUBLIC, "anon", "authenticated", "service_role";

ALTER TABLE "public"."customers"
  ADD CONSTRAINT "customers_owner_team_id_fkey" FOREIGN KEY (owner_team_id) REFERENCES better_supabase.teams(id) ON DELETE SET NULL;

CREATE VIEW "public"."customers_with_owner" WITH (security_invoker=true) AS  SELECT c.id,
    c.organization_id,
    c.name,
    c.status,
    c.owner_team_id,
    t.name AS owner_team_name
   FROM (public.customers c
     LEFT JOIN better_supabase.teams t ON (((t.id = c.owner_team_id) AND (t.tenant_id = c.organization_id))))
  WHERE (c.archived_at IS NULL);

REVOKE ALL ON TABLE "public"."customers_with_owner" FROM "anon";

CREATE INDEX customers_owner_team_id_idx ON public.customers USING btree (owner_team_id)
  WHERE (owner_team_id IS NOT NULL);

CREATE TRIGGER customers_owner_team_check
  BEFORE INSERT OR UPDATE OF owner_team_id ON public.customers
  FOR EACH ROW
  WHEN ((new.owner_team_id IS NOT NULL))
  EXECUTE FUNCTION public.customers_owner_team_check();

COMMENT ON FUNCTION "public"."customers_owner_team_check"() IS 'Keeps customers.owner_team_id inside the customer''s organization.';

COMMENT ON VIEW "public"."customers_with_owner" IS 'Open customers with the name of the team that owns them, read with the caller''s row level security on both tables.';

REVOKE ALL ON FUNCTION "public"."customers_owner_team_check"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."customers_owner_team_check"() TO "postgres";

REVOKE ALL ON TABLE "public"."customers_with_owner" FROM "authenticated";

GRANT SELECT ON TABLE "public"."customers_with_owner" TO "authenticated";

REVOKE ALL ON TABLE "public"."customers_with_owner" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."customers_with_owner" TO "postgres";

REVOKE ALL ON TABLE "public"."customers_with_owner" FROM "service_role";

GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE "public"."customers_with_owner" TO "service_role";
