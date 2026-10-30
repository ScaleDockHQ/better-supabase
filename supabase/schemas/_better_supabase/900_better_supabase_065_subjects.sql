-- better-supabase module: subjects
-- @bsb-block subjects@1 managed
-- @bsb-hash sha256:d77fcde78747c2a55f107a9ae89d6a02b44645c456683760732f3d634ead151d
-- The app-wide subject registry from config.subjects: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type, my_work across the installed blocks, and Realtime presence on presence:<type>:<id> for readers of the subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The app's subject registry (config.subjects, ADR 0020). Each function runs
-- as the caller, so the subject table's own policies decide what is visible.
create or replace function "better_supabase"."subject_types"()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select '{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[]
$$;
revoke execute on function "better_supabase"."subject_types"() from public, anon;
grant execute on function "better_supabase"."subject_types"() to authenticated, service_role;

create or replace function "better_supabase"."subject_title"(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_title.subject_type
    when 'message' then
      return (select s."body"::text from "better_supabase"."messages" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'conversation' then
      return (select s."title"::text from "better_supabase"."conversations" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'channel' then
      return (select s."name"::text from "better_supabase"."channels" s where s."id" = (subject_title.subject_id)::uuid);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'course' then
      return (select s."title"::text from "better_supabase"."courses" s where s."id" = (subject_title.subject_id)::uuid);
    when 'post' then
      return (select s."title"::text from "better_supabase"."posts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'engagement' then
      return (select s."title"::text from "better_supabase"."engagements" s where s."id" = (subject_title.subject_id)::uuid);
    when 'quote' then
      return (select s."title"::text from "better_supabase"."quotes" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'invoice' then
      return (select s."title"::text from "better_supabase"."invoices" s where s."id" = (subject_title.subject_id)::uuid);
    when 'ledger_account' then
      return (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'order' then
      return (select s."number"::text from "better_supabase"."orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'calendar_event' then
      return (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (subject_title.subject_id)::uuid);
    when 'booking' then
      return (select s."customer_name"::text from "better_supabase"."bookings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset' then
      return (select s."name"::text from "better_supabase"."assets" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset_location' then
      return (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lease' then
      return (select s."title"::text from "better_supabase"."lease_agreements" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_report' then
      return (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_line' then
      return (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (subject_title.subject_id)::uuid);
    when 'donation_fund' then
      return (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_order' then
      return (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'shipment' then
      return (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (subject_title.subject_id)::uuid);
    when 'contract' then
      return (select s."title"::text from "better_supabase"."contracts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'control' then
      return (select s."title"::text from "better_supabase"."controls" s where s."id" = (subject_title.subject_id)::uuid);
    when 'policy' then
      return (select s."title"::text from "better_supabase"."policies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'qualification_type' then
      return (select s."name"::text from "better_supabase"."qualification_types" s where s."id" = (subject_title.subject_id)::uuid);
    when 'incident' then
      return (select s."title"::text from "better_supabase"."incidents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'content_entry' then
      return (select s."title"::text from "better_supabase"."content_entries" s where s."id" = (subject_title.subject_id)::uuid);
    when 'form' then
      return (select s."title"::text from "better_supabase"."forms" s where s."id" = (subject_title.subject_id)::uuid);
    when 'document' then
      return (select s."name"::text from "better_supabase"."documents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'change_request' then
      return (select s."title"::text from "public"."change_requests" s where s."id" = (subject_title.subject_id)::uuid);
    when 'project' then
      return (select s."name"::text from "public"."projects" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."subject_title"(text, text) from public, anon;
grant execute on function "better_supabase"."subject_title"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."subject_url"(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_url.subject_type
    when 'company' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."companies" s where s."id" = (subject_url.subject_id)::uuid);
    when 'person' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."people" s where s."id" = (subject_url.subject_id)::uuid);
    when 'deal' then
      return (select '/crm/deals' from "better_supabase"."deals" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'work_item' then
      return (select '/work' from "better_supabase"."work_items" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select '/people' from "better_supabase"."employees" s where s."id" = (subject_url.subject_id)::uuid);
    when 'product' then
      return (select '/shop' from "better_supabase"."products" s where s."id" = (subject_url.subject_id)::uuid);
    when 'customer' then
      return (select '/customers/' || s."id"::text from "public"."customers" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'application' then
      return (select '/people/hiring' from "better_supabase"."applications" s where s."id" = (subject_url.subject_id)::uuid);
    when 'change_request' then
      return (select '/change-requests/' || s."id"::text from "public"."change_requests" s where s."id" = (subject_url.subject_id)::uuid);
    when 'project' then
      return (select '/projects/' || s."id"::text from "public"."projects" s where s."id" = (subject_url.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select '/projects/' || s."project_id"::text from "public"."tasks" s where s."id" = (subject_url.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."subject_url"(text, text) from public, anon;
grant execute on function "better_supabase"."subject_url"(text, text) to authenticated, service_role;

-- Titles and paths for many subjects in one call: refs is a JSON array of
-- { "type", "id" }, the result one of { type, id, title, url }. A row the
-- caller can't see, an unknown type or a soft-deleted row returns nothing.
create or replace function "better_supabase"."subject_titles"(refs jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'message', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."messages" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'message')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'conversation', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."conversations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'conversation')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'channel', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."channels" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'channel')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'course', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."courses" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'course')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'post', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."posts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'post')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'engagement', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."engagements" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'engagement')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'quote', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."quotes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'quote')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people'))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'invoice', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."invoices" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'invoice')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'booking', 'id', s."id"::text,
      'title', s."customer_name"::text, 'url', null::text))
    from "better_supabase"."bookings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'booking')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."assets" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset_location', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."asset_locations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset_location')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lease', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."lease_agreements" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lease')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_report', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."expense_reports" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_report')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_line', 'id', s."id"::text,
      'title', s."description"::text, 'url', null::text))
    from "better_supabase"."expense_lines" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_line')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'donation_fund', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."donation_funds" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'donation_fund')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_order', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."work_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'shipment', 'id', s."id"::text,
      'title', s."reference"::text, 'url', null::text))
    from "better_supabase"."shipments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'shipment')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'contract', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."contracts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'contract')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'control', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."controls" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'control')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'policy', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."policies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'policy')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'qualification_type', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."qualification_types" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'qualification_type')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'incident', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."incidents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'incident')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'content_entry', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."content_entries" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'content_entry')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'form', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."forms" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'form')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'change_request', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/change-requests/' || s."id"::text))
    from "public"."change_requests" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'change_request')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$$;
revoke execute on function "better_supabase"."subject_titles"(jsonb) from public, anon;
grant execute on function "better_supabase"."subject_titles"(jsonb) to authenticated, service_role;

-- True when the caller can see the subject row and, for an action with a
-- key in config.subjects.<type>.permissions, holds that key in the
-- subject's tenant (or on the record, through the subject's scope), and the
-- action's check function, when it names one, returns true for the row.
create or replace function "better_supabase"."can_subject"(subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end)
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end)
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.write'), false)
          else true
        end)
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end)
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."lease_agreements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end)
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end)
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end)
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end)
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end)
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end)
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end)
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.manage'), false)
          else true
        end)
      );
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.manage'), false)
          else true
        end)
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.manage'), false)
          else true
        end)
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end)
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end)
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false)
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then coalesce("better_supabase"."drive_can_comment"(s."id"), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$$;
revoke execute on function "better_supabase"."can_subject"(text, text, text) from public, anon;
grant execute on function "better_supabase"."can_subject"(text, text, text) to authenticated, service_role;

-- A record page's header and tab badges in one call: the subject's title and
-- path, how many rows each named section has and whether any is newer than
-- seen_at. Runs as the caller, so each count is what the caller can read;
-- null when the caller can't read the subject. An unknown section is left out.
create or replace function "better_supabase"."record_summary"(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
  v_seen timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > 20 then
    raise exception 'record_summary takes at most 20 sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not "better_supabase"."can_subject"(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
  if 'comments' = any (record_summary.sections) then
    select count(*), max(x."sent_at")
      into v_count, v_latest
      from "better_supabase"."messages" x
      join "better_supabase"."conversations" c on c."id" = x."conversation_id"
        and c."kind" = 'subject'
      where c."subject_type"::text = record_summary.subject_type
        and c."subject_id"::text = record_summary.subject_id
        and x."sent_at" is not null and x."deleted_at" is null;
    v_seen := coalesce((select "better_supabase"."conversation_read_at"(c."id") from "better_supabase"."conversations" c
        where c."kind" = 'subject'
          and c."subject_type" = record_summary.subject_type
          and c."subject_id" = record_summary.subject_id), record_summary.seen_at);
    v_counts := v_counts || jsonb_build_object('comments', v_count);
    v_unread := v_unread || jsonb_build_object('comments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  if 'attachments' = any (record_summary.sections) then
    select count(*), max(x."uploaded_at")
      into v_count, v_latest
      from "better_supabase"."attachments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."uploaded_at" is not null and x."status" <> 'infected';
    v_seen := record_summary.seen_at;
    v_counts := v_counts || jsonb_build_object('attachments', v_count);
    v_unread := v_unread || jsonb_build_object('attachments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', "better_supabase"."subject_title"(record_summary.subject_type, record_summary.subject_id),
    'url', "better_supabase"."subject_url"(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$$;
revoke execute on function "better_supabase"."record_summary"(text, text, text[], timestamptz) from public, anon;
grant execute on function "better_supabase"."record_summary"(text, text, text[], timestamptz) to authenticated, service_role;

-- can_subject for another user, for server code that decides who receives
-- an event. It reads the row past its policies and asks can_user for the
-- action's key in config.subjects.<type>.permissions, so an action without
-- a key is false and a share-link grant never counts. A provider that
-- can't answer for others (no idsWithFor) gives false.
create or replace function "better_supabase"."can_subject_for"(member uuid, subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case can_subject_for.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'channels.manage'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.manage'), false)
          else false
        end
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.write'), false)
          else false
        end
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.write'), false)
          else false
        end
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.manage'), false)
          else false
        end
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."lease_agreements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.manage'), false)
          else false
        end
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          else false
        end
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.submit'), false)
          else false
        end
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.manage'), false)
          else false
        end
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.manage'), false)
          else false
        end
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.manage'), false)
          else false
        end
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.write'), false)
          else false
        end
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.manage'), false)
          else false
        end
      );
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.manage'), false)
          else false
        end
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.manage'), false)
          else false
        end
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.write'), false)
          else false
        end
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.write'), false)
          else false
        end
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.manage'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false)
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then false
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then false
          when 'fields' then false
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$$;
revoke execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) to service_role;

-- The caller's own reminders sent in the last week, for my_work. Reminders
-- have no read policy, so this reads them past it, keeping only the caller's.
create or replace function "better_supabase"."my_reminders_due"(tenant uuid default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id", r."subject_type"::text,
    r."subject_id"::text, max(d."occurrence_at")
  from "better_supabase"."reminders" r
  join "better_supabase"."reminder_deliveries" d on d."reminder_id" = r."id"
  where r."user_id" = (select auth.uid())
    and (my_reminders_due.tenant is null or r."tenant_id" = my_reminders_due.tenant)
    and d."sent_at" > now() - interval '7 days'
  group by 1, 2, 3
$$;
revoke execute on function "better_supabase"."my_reminders_due"(uuid) from public, anon;
grant execute on function "better_supabase"."my_reminders_due"(uuid) to authenticated, service_role;

-- What waits on the caller across the installed blocks, newest first. Runs as
-- the caller, so each row is one they can read.
create or replace function "better_supabase"."my_work"(tenant uuid default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, "better_supabase"."subject_title"(w.subject_type, w.subject_id)),
      'url', "better_supabase"."subject_url"(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    select 'mention'::text, c."subject_type"::text, c."subject_id"::text, m."id"::text, null::text,
      m."sent_at"
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id" and c."kind" = 'subject'
    where v_me = any (m."mentions")
      and m."deleted_at" is null
      and m."sent_at" > now() - interval '30 days'
      and (my_work.tenant is null or m."tenant_id" = my_work.tenant)
    union all
    select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from "better_supabase"."my_reminders_due"(my_work.tenant) d
    where "better_supabase"."can_subject"(d.subject_type, d.subject_id, 'read')
    union all
    select 'approval'::text, r."subject_type"::text, r."subject_id"::text, r."id"::text, null::text,
      r."created_at"
    from "better_supabase"."approval_requests" r
    where r."status" = 'pending'
      and (r."expires_at" is null or r."expires_at" > now())
      and (my_work.tenant is null or r."tenant_id" = my_work.tenant)
      and "better_supabase"."approval_eligible"(r."id")
    union all
    select 'assigned'::text, 'work_item'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."work_item_assignees" a
    join "better_supabase"."work_items" i on i."id" = a."work_item_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'assigned'::text, 'maintenance_request'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."maintenance_request_assignees" a
    join "better_supabase"."maintenance_requests" i on i."id" = a."maintenance_request_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'sla'::text, k."subject_type"::text, k."subject_id"::text, k."id"::text, null::text,
      k."due_at"
    from "better_supabase"."sla_clocks" k
    where k."subject_type" = 'work_item'
      and k."warned_at" is not null
      and k."met_at" is null
      and (my_work.tenant is null or k."tenant_id" = my_work.tenant)
      and exists (
        select 1 from "better_supabase"."work_item_assignees" a
        where a."work_item_id"::text = k."subject_id"::text
          and a."user_id" = v_me)
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), 200)
    ) w
  );
end;
$$;
revoke execute on function "better_supabase"."my_work"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."my_work"(uuid, integer) to authenticated, service_role;

-- Whether the caller may join presence topic `topic`
-- (presence:<type>:<id>): they can read that subject.
create or replace function "better_supabase"."subject_presence_allowed"(topic text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^presence:([a-z][a-z0-9_-]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce("better_supabase"."can_subject"(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$$;
revoke execute on function "better_supabase"."subject_presence_allowed"(text) from public, anon;
grant execute on function "better_supabase"."subject_presence_allowed"(text) to authenticated, service_role;

do $$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_subject_presence_receive on realtime.messages;
create policy bsb_subject_presence_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic())));
        drop policy if exists bsb_subject_presence_send on realtime.messages;
create policy bsb_subject_presence_send on realtime.messages
  for insert to authenticated
  with check ((realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic()))) and (select better_supabase.actor_may_write()));
  end if;
end;
$$;

-- blocks.subjects.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."subject_types"()
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_types"() $$;
revoke execute on function "api"."subject_types"() from public, anon;
grant execute on function "api"."subject_types"() to authenticated, service_role;

create or replace function "api"."subject_title"(subject_type text, subject_id text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_title"($1, $2) $$;
revoke execute on function "api"."subject_title"(text, text) from public, anon;
grant execute on function "api"."subject_title"(text, text) to authenticated, service_role;

create or replace function "api"."subject_url"(subject_type text, subject_id text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_url"($1, $2) $$;
revoke execute on function "api"."subject_url"(text, text) from public, anon;
grant execute on function "api"."subject_url"(text, text) to authenticated, service_role;

create or replace function "api"."subject_titles"(refs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_titles"($1) $$;
revoke execute on function "api"."subject_titles"(jsonb) from public, anon;
grant execute on function "api"."subject_titles"(jsonb) to authenticated, service_role;

create or replace function "api"."can_subject"(subject_type text, subject_id text, action text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_subject"($1, $2, $3) $$;
revoke execute on function "api"."can_subject"(text, text, text) from public, anon;
grant execute on function "api"."can_subject"(text, text, text) to authenticated, service_role;

create or replace function "api"."record_summary"(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_summary"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_summary"(text, text, text[], timestamptz) from public, anon;
grant execute on function "api"."record_summary"(text, text, text[], timestamptz) to authenticated, service_role;

create or replace function "api"."can_subject_for"(member uuid, subject_type text, subject_id text, action text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_subject_for"($1, $2, $3, $4) $$;
revoke execute on function "api"."can_subject_for"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."can_subject_for"(uuid, text, text, text) to service_role;

create or replace function "api"."my_reminders_due"(tenant uuid default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."my_reminders_due"($1) $$;
revoke execute on function "api"."my_reminders_due"(uuid) from public, anon;
grant execute on function "api"."my_reminders_due"(uuid) to authenticated, service_role;

create or replace function "api"."my_work"(tenant uuid default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_work"($1, $2) $$;
revoke execute on function "api"."my_work"(uuid, integer) from public, anon;
grant execute on function "api"."my_work"(uuid, integer) to authenticated, service_role;

create or replace function "api"."subject_presence_allowed"(topic text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_presence_allowed"($1) $$;
revoke execute on function "api"."subject_presence_allowed"(text) from public, anon;
grant execute on function "api"."subject_presence_allowed"(text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
