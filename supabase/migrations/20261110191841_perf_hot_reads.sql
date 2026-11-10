SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contacts_json (
  ids    uuid[] DEFAULT NULL::uuid[],
  tenant uuid   DEFAULT NULL::uuid,
  term   text   DEFAULT NULL::text
)
  RETURNS TABLE (
    conversation    uuid,
    contact         jsonb,
    contact_read_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  with c as (
    select v."id" as id, v."tenant_id" as scope, v."contact_id" as person
    from "better_supabase"."inbox_conversations" v
    where (inbox_contacts_json.ids is not null or inbox_contacts_json.term is not null)
      and (inbox_contacts_json.ids is null or v."id" = any (inbox_contacts_json.ids))
      and (inbox_contacts_json.tenant is null or v."tenant_id" = inbox_contacts_json.tenant)
  ), staff as (
    select t.scope, (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(coalesce(better_supabase.can('tenant', t.scope, 'inbox.read'), false), false)) as ok
    from (select distinct c.scope from c) t
  )
  select c.id,
    case when s.ok or p."user_id" = (select auth.uid()) then
      jsonb_build_object('id', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'avatar_url', p."avatar_url", 'user_id', p."user_id")
    end,
    case when s.ok then (
      select k."last_read_at" from "better_supabase"."conversation_members" k
      where k."conversation_id" = c.id and k."user_id" = p."user_id"
    ) end
  from c
  join staff s on s.scope = c.scope
  join "better_supabase"."people" p on p."id" = c.person
  where inbox_contacts_json.term is null
    or ((s.ok or p."user_id" = (select auth.uid())) and (p."name" ilike '%' || inbox_contacts_json.term || '%'
      or p."email" ilike '%' || inbox_contacts_json.term || '%'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inbox_conversations (
  tenant uuid  DEFAULT NULL::uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    with page as materialized (
      select v."id" as id, v."inbox_id" as inbox, v."last_message_at" as last_message_at, to_jsonb(v) as body
      from "better_supabase"."inbox_conversations" v
      where (list_inbox_conversations.tenant is null or v."tenant_id" = list_inbox_conversations.tenant)
        and (filter ->> 'inbox_id' is null or v."inbox_id" = (filter ->> 'inbox_id')::uuid)
        and (coalesce(filter ->> 'status', 'open') = 'all' or v."status" = coalesce(filter ->> 'status', 'open'))
        and (case filter ->> 'assignee'
          when 'me' then v."assignee_id" = (select auth.uid())
          when 'unassigned' then v."assignee_id" is null
          else filter ->> 'assignee' is null or v."assignee_id" = (filter ->> 'assignee')::uuid end)
        and (filter ->> 'team_id' is null or v."team_id" = (filter ->> 'team_id')::uuid)
        and (filter ->> 'contact_id' is null or v."contact_id" = (filter ->> 'contact_id')::uuid)
        and (nullif(filter ->> 'search', '') is null
          or v."subject" ilike '%' || (filter ->> 'search') || '%'
          or v."last_message_preview" ilike '%' || (filter ->> 'search') || '%'
          or v."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, list_inbox_conversations.tenant, filter ->> 'search') m))
        and (filter -> 'before' is null
          or (v."last_message_at", v."id") < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
      order by v."last_message_at" desc, v."id" desc
      limit least(greatest(coalesce((filter ->> 'limit')::integer, 50), 1), 200)
    ), contacts as materialized (
      select c.conversation, c.contact, c.contact_read_at
      from "better_supabase"."inbox_contacts_json"((select coalesce(array_agg(page.id), '{}') from page)) c
    )
    select coalesce(jsonb_agg(
      page.body || jsonb_build_object(
        'contact', contacts.contact,
        'inbox', box.item,
        'last_read_at', seen.at,
        'contact_read_at', contacts.contact_read_at,
        'unread', page.last_message_at > coalesce(seen.at, '-infinity'::timestamptz))
      order by page.last_message_at desc, page.id desc), '[]'::jsonb)
    from page
    left join contacts on contacts.conversation = page.id
    left join lateral (
      select jsonb_build_object('id', i."id", 'name', i."name", 'channel', i."channel") as item
      from "better_supabase"."inboxes" i where i."id" = page.inbox
    ) box on true
    left join lateral (
      select k."last_read_at" as at
      from "better_supabase"."conversation_members" k
      where k."conversation_id" = page.id and k."user_id" = (select auth.uid())
    ) seen on true
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.island_counts (
  args jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'customers', (select count(*) from (select 1 from public.customers as c where c.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'notes', (select count(*) from (select 1 from public.notes as n where n.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'contacts', (select count(*) from (select 1 from public.contacts as c where c.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'tags', (select count(*) from (select 1 from public.tags as t where t.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'tasks', (select count(*) from (select 1 from public.tasks as t where t.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped)
  );
$function$;

CREATE INDEX customers_organization_id_name_idx ON public.customers USING btree (organization_id, name);

COMMENT ON FUNCTION "public"."island_counts"(jsonb) IS 'The islands page data: row counts of five tables in the active organization, each stopping at 10,000 (a lower bound above that). better_supabase.bootstrap_islands runs it as the caller, so RLS scopes every count.';

REVOKE ALL ON FUNCTION "better_supabase"."inbox_contacts_json"(uuid[], uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_contacts_json"(uuid[], uuid, text) TO "authenticated", "service_role";
