import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import {
  COMPONENT_STATUSES,
  INCIDENT_RESERVED,
  INCIDENT_SEVERITIES,
  INCIDENT_STATUSES,
} from "./incidents-shared.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The component, incident, timeline and postmortem functions. */
export function incidentsFunctions(ctx: ModuleContext): string {
  const components = ctx.table("components");
  const history = ctx.table("history");
  const incidents = ctx.table("incidents");
  const updates = ctx.table("updates");
  const impacts = ctx.table("impacts");
  const postmortems = ctx.table("postmortems");
  const c = (column: string): string => ctx.col("components", column);
  const h = (column: string): string => ctx.col("history", column);
  const i = (column: string): string => ctx.col("incidents", column);
  const u = (column: string): string => ctx.col("updates", column);
  const m = (column: string): string => ctx.col("impacts", column);
  const pm = (column: string): string => ctx.col("postmortems", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("incidents");
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);
  const members = ctx.of("tenant");
  const incidentType = sqlString(ctx.resolved.entityNaming.rename("incident"));
  const extras = ctx.extraColumns("incidents", INCIDENT_RESERVED);
  const extra = extraFieldsArg(extras);
  const ranks = `array[${list(COMPONENT_STATUSES)}]`;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("INCIDENTS_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("INCIDENTS_INVALID", message, "22023");

  const incidentNotFound = fail(
    "INCIDENT_NOT_FOUND",
    "incident not found",
    "P0002",
  );

  const componentNotFound = fail(
    "STATUS_COMPONENT_NOT_FOUND",
    "status component not found",
    "P0002",
  );

  const isMember = (tenant: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} mm where mm.${members.col("memberships", "tenant")} = ${tenant} and mm.${members.col("memberships", "user")} = ${user})`;

  const componentJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'name', ${row}.${c("name")}, 'description', ${row}.${c("description")}, 'group', ${row}.${c("group")}, 'public', ${row}.${c("public")}, 'status', ${row}.${c("status")}, 'position', ${row}.${c("position")}, 'createdAt', ${row}.${c("createdAt")}, 'updatedAt', ${row}.${c("updatedAt")})`;

  const incidentJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${i("id")}, 'organizationId', ${row}.${i("tenant")}, 'title', ${row}.${i("title")}, 'description', ${row}.${i("description")}, 'severity', ${row}.${i("severity")}, 'status', ${row}.${i("status")}, 'public', ${row}.${i("public")}, 'commanderId', ${row}.${i("commander")}, 'startedAt', ${row}.${i("startedAt")}, 'resolvedAt', ${row}.${i("resolvedAt")}, 'createdBy', ${row}.${i("createdBy")}, 'createdAt', ${row}.${i("createdAt")}, 'updatedAt', ${row}.${i("updatedAt")}, 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im.${m("component")}, 'name', ic.${c("name")}, 'impact', im.${m("impact")}) order by ic.${c("position")}, ic.${c("name")}), '[]'::jsonb) from ${impacts} im join ${components} ic on ic.${c("id")} = im.${m("component")} where im.${m("incident")} = ${row}.${i("id")})${extraFieldsJson(row, extras)})`;

  const updateJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${u("id")}, 'incidentId', ${row}.${u("incident")}, 'status', ${row}.${u("status")}, 'body', ${row}.${u("body")}, 'public', ${row}.${u("public")}, 'authorId', ${row}.${u("author")}, 'createdAt', ${row}.${u("createdAt")})`;

  const postmortemJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${pm("id")}, 'incidentId', ${row}.${pm("incident")}, 'summary', ${row}.${pm("summary")}, 'impact', ${row}.${pm("impact")}, 'rootCause', ${row}.${pm("rootCause")}, 'resolution', ${row}.${pm("resolution")}, 'actionItems', ${row}.${pm("actionItems")}, 'status', ${row}.${pm("status")}, 'publishedAt', ${row}.${pm("publishedAt")}, 'authorId', ${row}.${pm("author")}, 'createdAt', ${row}.${pm("createdAt")}, 'updatedAt', ${row}.${pm("updatedAt")})`;

  const incidentRecord = (
    type: string,
    payload: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload,
      subject: `'incidents/' || v_row.${i("id")}::text`,
      tenant: `v_row.${i("tenant")}`,
      audit: {
        category: "data",
        targetType: "incident",
        recordId: `v_row.${i("id")}::text`,
        summary,
      },
    });

  return `
-- Sets each component's status to the worst impact of the open incidents on
-- it, and keeps the uptime history in step.
create or replace function ${fn("incident_refresh_components")}(component_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_component ${components}%rowtype;
  v_status text;
begin
  for v_component in
    select * from ${components} x where x.${c("id")} = any(incident_refresh_components.component_ids) for update
  loop
    select coalesce(
      (${ranks})[max(array_position(${ranks}, im.${m("impact")}))],
      'operational'
    ) into v_status
    from ${impacts} im
    join ${incidents} ii on ii.${i("id")} = im.${m("incident")}
    where im.${m("component")} = v_component.${c("id")} and ii.${i("status")} <> 'resolved';
    continue when v_status = v_component.${c("status")};
    update ${components} x set ${c("status")} = v_status, ${c("updatedAt")} = now()
      where x.${c("id")} = v_component.${c("id")};
    update ${history} x set ${h("endedAt")} = now()
      where x.${h("component")} = v_component.${c("id")} and x.${h("endedAt")} is null;
    insert into ${history} (${h("tenant")}, ${h("component")}, ${h("status")})
    values (v_component.${c("tenant")}, v_component.${c("id")}, v_status);
    ${ctx.record({
      type: "status_component.changed",
      payload: `jsonb_build_object('organizationId', v_component.${c("tenant")}, 'statusComponentId', v_component.${c("id")}, 'status', v_status, 'previousStatus', v_component.${c("status")})`,
      subject: `'status-components/' || v_component.${c("id")}::text`,
      tenant: `v_component.${c("tenant")}`,
      audit: {
        category: "data",
        targetType: "status_component",
        recordId: `v_component.${c("id")}::text`,
        summary: `'status of ' || v_component.${c("name")} || ' changed to ' || v_status`,
      },
    })}
  end loop;
end;
$$;
${serviceGrant(`${fn("incident_refresh_components")}(uuid[])`)}

-- Replaces an incident's impacts with [{ componentId, impact }] and refreshes
-- the components it touched before and after.
create or replace function ${fn("incident_apply_impacts")}(incident_id uuid, impacts jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
  v_before uuid[];
  v_item jsonb;
  v_component uuid;
begin
  select * into v_row from ${incidents} x where x.${i("id")} = incident_apply_impacts.incident_id;
  if jsonb_typeof(coalesce(incident_apply_impacts.impacts, '[]'::jsonb)) <> 'array' then
    ${invalid("impacts must be an array")}
  end if;
  select coalesce(array_agg(x.${m("component")}), '{}') into v_before
    from ${impacts} x where x.${m("incident")} = v_row.${i("id")};
  delete from ${impacts} x where x.${m("incident")} = v_row.${i("id")};
  for v_item in select value from jsonb_array_elements(coalesce(incident_apply_impacts.impacts, '[]'::jsonb))
  loop
    v_component := nullif(v_item ->> 'componentId', '')::uuid;
    if not exists (
      select 1 from ${components} x where x.${c("id")} = v_component and x.${c("tenant")} = v_row.${i("tenant")}
    ) then
      ${componentNotFound}
    end if;
    if coalesce(v_item ->> 'impact', '') not in (${list(COMPONENT_STATUSES.slice(1))}) then
      ${invalid("impact must be degraded, partial_outage, major_outage or maintenance")}
    end if;
    insert into ${impacts} (${m("tenant")}, ${m("incident")}, ${m("component")}, ${m("impact")})
    values (v_row.${i("tenant")}, v_row.${i("id")}, v_component, v_item ->> 'impact')
    on conflict (${m("incident")}, ${m("component")}) do update set ${m("impact")} = excluded.${m("impact")};
  end loop;
  perform ${fn("incident_refresh_components")}(
    v_before || array(select x.${m("component")} from ${impacts} x where x.${m("incident")} = v_row.${i("id")})
  );
end;
$$;
${serviceGrant(`${fn("incident_apply_impacts")}(uuid, jsonb)`)}

-- Creates a component by name, or changes one (component_id).
create or replace function ${fn("save_status_component")}(tenant ${idType}, name text, description text default null, group_name text default null, is_public boolean default true, sort_position integer default 0, component_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${components}%rowtype;
begin
  if not ${allowed("save_status_component.tenant", manage)} then
    ${forbidden("not allowed to manage status components")}
  end if;
  if nullif(trim(save_status_component.name), '') is null then
    ${invalid("a component needs a name")}
  end if;
  if save_status_component.component_id is null then
    insert into ${components} (${c("tenant")}, ${c("name")}, ${c("description")}, ${c("group")}, ${c("public")}, ${c("position")})
    values (save_status_component.tenant, trim(save_status_component.name), save_status_component.description,
      nullif(trim(save_status_component.group_name), ''), coalesce(save_status_component.is_public, true), coalesce(save_status_component.sort_position, 0))
    returning * into v_row;
    insert into ${history} (${h("tenant")}, ${h("component")}, ${h("status")})
    values (v_row.${c("tenant")}, v_row.${c("id")}, v_row.${c("status")});
  else
    update ${components} x set ${c("name")} = trim(save_status_component.name), ${c("description")} = save_status_component.description,
      ${c("group")} = nullif(trim(save_status_component.group_name), ''), ${c("public")} = coalesce(save_status_component.is_public, true),
      ${c("position")} = coalesce(save_status_component.sort_position, 0), ${c("updatedAt")} = now()
      where x.${c("id")} = save_status_component.component_id and x.${c("tenant")} = save_status_component.tenant
      returning * into v_row;
    if not found then
      ${componentNotFound}
    end if;
  end if;
  return ${componentJson("v_row")};
end;
$$;
${userGrant(`${fn("save_status_component")}(${idType}, text, text, text, boolean, integer, uuid)`)}

create or replace function ${fn("delete_status_component")}(component_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${components}%rowtype;
begin
  select * into v_row from ${components} x where x.${c("id")} = delete_status_component.component_id;
  if not found then
    ${componentNotFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, manage)} then
    ${forbidden("not allowed to manage status components")}
  end if;
  delete from ${components} x where x.${c("id")} = v_row.${c("id")};
  return jsonb_build_object('id', v_row.${c("id")}, 'deleted', true);
end;
$$;
${userGrant(`${fn("delete_status_component")}(uuid)`)}

create or replace function ${fn("list_status_components")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${componentJson("x")} order by x.${c("position")}, x.${c("name")}), '[]'::jsonb)
  from ${components} x
  where x.${c("tenant")} = list_status_components.tenant
$$;
${userGrant(`${fn("list_status_components")}(${idType})`)}

-- Opens an incident. attrs: title (required), description, severity (sev1
-- to sev4, default sev3), public, commanderId, message (the first timeline
-- update) and impacts ([{ componentId, impact }]).
${extra.drop(fn("open_incident"), `${idType}, jsonb`)}
create or replace function ${fn("open_incident")}(tenant ${idType}, attrs jsonb${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
  v_claims text;
begin
  if not ${allowed("open_incident.tenant", write)} then
    ${forbidden("not allowed to open incidents")}
  end if;
  if jsonb_typeof(open_incident.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  if nullif(trim(open_incident.attrs ->> 'title'), '') is null then
    ${invalid("an incident needs a title")}
  end if;
  if coalesce(open_incident.attrs ->> 'severity', 'sev3') not in (${list(INCIDENT_SEVERITIES)}) then
    ${invalid("severity must be sev1, sev2, sev3 or sev4")}
  end if;
  if open_incident.attrs ? 'commanderId' and open_incident.attrs ->> 'commanderId' is not null
    and not ${isMember("open_incident.tenant", "(open_incident.attrs ->> 'commanderId')::uuid")} then
    ${invalid("the commander must be a member of the organization")}
  end if;
  insert into ${incidents} (${i("tenant")}, ${i("title")}, ${i("description")}, ${i("severity")}, ${i("public")}, ${i("commander")}, ${i("createdBy")})
  values (open_incident.tenant, trim(open_incident.attrs ->> 'title'), open_incident.attrs ->> 'description',
    coalesce(open_incident.attrs ->> 'severity', 'sev3'), coalesce((open_incident.attrs ->> 'public')::boolean, false),
    (open_incident.attrs ->> 'commanderId')::uuid, auth.uid())
  returning * into v_row;${writeExtraColumns(incidents, extras, "open_incident.fields", `x.${i("id")} = v_row.${i("id")}`, "v_row")}
  if nullif(trim(open_incident.attrs ->> 'message'), '') is not null then
    insert into ${updates} (${u("tenant")}, ${u("incident")}, ${u("status")}, ${u("body")}, ${u("public")}, ${u("author")})
    values (v_row.${i("tenant")}, v_row.${i("id")}, v_row.${i("status")}, trim(open_incident.attrs ->> 'message'), v_row.${i("public")}, auth.uid());
  end if;
  perform ${fn("incident_apply_impacts")}(v_row.${i("id")}, open_incident.attrs -> 'impacts');
  ${incidentRecord(
    "incident.opened",
    `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'incidentId', v_row.${i("id")}, 'title', v_row.${i("title")}, 'severity', v_row.${i("severity")}, 'status', v_row.${i("status")}, 'public', v_row.${i("public")})`,
    `'opened incident ' || v_row.${i("title")}`,
  )}
  if v_row.${i("commander")} is not null and v_row.${i("commander")} is distinct from auth.uid() then
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'incident.opened',
      'tenant', v_row.${i("tenant")},
      'actor', auth.uid(),
      'subject_type', ${incidentType},
      'subject_id', v_row.${i("id")}::text,
      'summary', v_row.${i("title")},
      'recipients', to_jsonb(array[v_row.${i("commander")}]),
      'key', 'incident.opened:' || v_row.${i("id")}::text,
      'data', jsonb_build_object('incidentId', v_row.${i("id")}, 'severity', v_row.${i("severity")})
    )`,
      { indent: "    " },
    )}
  end if;
  return ${incidentJson("v_row")};
end;
$$;
${userGrant(`${fn("open_incident")}(${idType}, jsonb${extra.type})`)}

-- Changes an incident. attrs: title, description, severity, public and
-- commanderId; a key left out keeps its value. The status moves only
-- through post_incident_update.
${extra.drop(fn("update_incident"), "uuid, jsonb")}
create or replace function ${fn("update_incident")}(incident_id uuid, attrs jsonb${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
begin
  select * into v_row from ${incidents} x where x.${i("id")} = update_incident.incident_id for update;
  if not found then
    ${incidentNotFound}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, write)} then
    ${forbidden("not allowed to change incidents")}
  end if;
  if jsonb_typeof(update_incident.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  if update_incident.attrs ? 'title' and nullif(trim(update_incident.attrs ->> 'title'), '') is null then
    ${invalid("an incident needs a title")}
  end if;
  if update_incident.attrs ? 'severity' and coalesce(update_incident.attrs ->> 'severity', '') not in (${list(INCIDENT_SEVERITIES)}) then
    ${invalid("severity must be sev1, sev2, sev3 or sev4")}
  end if;
  if update_incident.attrs ->> 'commanderId' is not null
    and not ${isMember(`v_row.${i("tenant")}`, "(update_incident.attrs ->> 'commanderId')::uuid")} then
    ${invalid("the commander must be a member of the organization")}
  end if;
  update ${incidents} x set
    ${i("title")} = case when update_incident.attrs ? 'title' then trim(update_incident.attrs ->> 'title') else x.${i("title")} end,
    ${i("description")} = case when update_incident.attrs ? 'description' then update_incident.attrs ->> 'description' else x.${i("description")} end,
    ${i("severity")} = case when update_incident.attrs ? 'severity' then update_incident.attrs ->> 'severity' else x.${i("severity")} end,
    ${i("public")} = case when update_incident.attrs ? 'public' then coalesce((update_incident.attrs ->> 'public')::boolean, false) else x.${i("public")} end,
    ${i("commander")} = case when update_incident.attrs ? 'commanderId' then (update_incident.attrs ->> 'commanderId')::uuid else x.${i("commander")} end,
    ${i("updatedAt")} = now()
    where x.${i("id")} = v_row.${i("id")}
    returning * into v_row;${writeExtraColumns(incidents, extras, "update_incident.fields", `x.${i("id")} = v_row.${i("id")}`, "v_row")}
  return ${incidentJson("v_row")};
end;
$$;
${userGrant(`${fn("update_incident")}(uuid, jsonb${extra.type})`)}

-- Adds a timeline update and moves the incident to its status (null keeps
-- the current one). is_public defaults to the incident's own flag; a public
-- update on a private incident still stays off the status page.
create or replace function ${fn("post_incident_update")}(incident_id uuid, status text, body text, is_public boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
  v_from text;
  v_update ${updates}%rowtype;
begin
  select * into v_row from ${incidents} x where x.${i("id")} = post_incident_update.incident_id for update;
  if not found then
    ${incidentNotFound}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, write)} then
    ${forbidden("not allowed to update incidents")}
  end if;
  if post_incident_update.status is not null and post_incident_update.status not in (${list(INCIDENT_STATUSES)}) then
    ${invalid("status must be investigating, identified, monitoring or resolved")}
  end if;
  if nullif(trim(post_incident_update.body), '') is null then
    ${invalid("an update needs a body")}
  end if;
  v_from := v_row.${i("status")};
  update ${incidents} x set
    ${i("status")} = coalesce(post_incident_update.status, x.${i("status")}),
    ${i("resolvedAt")} = case
      when coalesce(post_incident_update.status, x.${i("status")}) <> 'resolved' then null
      else coalesce(x.${i("resolvedAt")}, now())
    end,
    ${i("updatedAt")} = now()
    where x.${i("id")} = v_row.${i("id")}
    returning * into v_row;
  insert into ${updates} (${u("tenant")}, ${u("incident")}, ${u("status")}, ${u("body")}, ${u("public")}, ${u("author")})
  values (v_row.${i("tenant")}, v_row.${i("id")}, v_row.${i("status")}, trim(post_incident_update.body),
    coalesce(post_incident_update.is_public, v_row.${i("public")}), auth.uid())
  returning * into v_update;
  if v_from is distinct from v_row.${i("status")} then
    perform ${fn("incident_refresh_components")}(
      array(select x.${m("component")} from ${impacts} x where x.${m("incident")} = v_row.${i("id")})
    );
  end if;
  ${incidentRecord(
    "incident.updated",
    `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'incidentId', v_row.${i("id")}, 'updateId', v_update.${u("id")}, 'status', v_row.${i("status")}, 'public', v_update.${u("public")})`,
    `'posted an update on incident ' || v_row.${i("title")}`,
  )}
  if v_row.${i("status")} = 'resolved' and v_from <> 'resolved' then
    ${incidentRecord(
      "incident.resolved",
      `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'incidentId', v_row.${i("id")}, 'severity', v_row.${i("severity")})`,
      `'resolved incident ' || v_row.${i("title")}`,
    )}
  end if;
  return ${updateJson("v_update")};
end;
$$;
${userGrant(`${fn("post_incident_update")}(uuid, text, text, boolean)`)}

create or replace function ${fn("set_incident_impacts")}(incident_id uuid, impacts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
begin
  select * into v_row from ${incidents} x where x.${i("id")} = set_incident_impacts.incident_id for update;
  if not found then
    ${incidentNotFound}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, write)} then
    ${forbidden("not allowed to change incidents")}
  end if;
  perform ${fn("incident_apply_impacts")}(v_row.${i("id")}, set_incident_impacts.impacts);
  return ${incidentJson("v_row")};
end;
$$;
${userGrant(`${fn("set_incident_impacts")}(uuid, jsonb)`)}

create or replace function ${fn("get_incident")}(incident_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${incidentJson("x")} || jsonb_build_object(
    'updates', (select coalesce(jsonb_agg(${updateJson("y")} order by y.${u("createdAt")}, y.${u("id")}), '[]'::jsonb) from ${updates} y where y.${u("incident")} = x.${i("id")}),
    'postmortem', (select ${postmortemJson("z")} from ${postmortems} z where z.${pm("incident")} = x.${i("id")})
  )
  from ${incidents} x
  where x.${i("id")} = get_incident.incident_id
$$;
${userGrant(`${fn("get_incident")}(uuid)`)}

-- The incidents, newest first. status: open, resolved or null for both;
-- before: the startedAt of the last row of the previous page.
create or replace function ${fn("list_incidents")}(tenant ${idType}, status text default null, severity text default null, component_id uuid default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(row_json order by started desc, id desc), '[]'::jsonb)
  from (
    select ${incidentJson("x")} as row_json, x.${i("startedAt")} as started, x.${i("id")} as id
    from ${incidents} x
    where x.${i("tenant")} = list_incidents.tenant
      and (list_incidents.status is null
        or (list_incidents.status = 'open' and x.${i("status")} <> 'resolved')
        or (list_incidents.status = 'resolved' and x.${i("status")} = 'resolved'))
      and (list_incidents.severity is null or x.${i("severity")} = list_incidents.severity)
      and (list_incidents.component_id is null or exists (
        select 1 from ${impacts} y where y.${m("incident")} = x.${i("id")} and y.${m("component")} = list_incidents.component_id
      ))
      and (list_incidents.before is null or x.${i("startedAt")} < list_incidents.before)
    order by x.${i("startedAt")} desc, x.${i("id")} desc
    limit ${pageSize("list_incidents.page_size", 50, 200)}
  ) page
$$;
${userGrant(`${fn("list_incidents")}(${idType}, text, text, uuid, timestamptz, integer)`)}

-- Writes the incident's postmortem. attrs: summary, impact, rootCause,
-- resolution and actionItems ([{ title, ownerId, done }]); a key left out
-- keeps its value.
create or replace function ${fn("save_postmortem")}(incident_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
  v_post ${postmortems}%rowtype;
begin
  select * into v_row from ${incidents} x where x.${i("id")} = save_postmortem.incident_id;
  if not found then
    ${incidentNotFound}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, write)} then
    ${forbidden("not allowed to write postmortems")}
  end if;
  if jsonb_typeof(save_postmortem.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  if save_postmortem.attrs ? 'actionItems' and jsonb_typeof(save_postmortem.attrs -> 'actionItems') is distinct from 'array' then
    ${invalid("actionItems must be an array")}
  end if;
  insert into ${postmortems} (${pm("tenant")}, ${pm("incident")}, ${pm("author")})
  values (v_row.${i("tenant")}, v_row.${i("id")}, auth.uid())
  on conflict (${pm("incident")}) do nothing;
  update ${postmortems} x set
    ${pm("summary")} = case when save_postmortem.attrs ? 'summary' then save_postmortem.attrs ->> 'summary' else x.${pm("summary")} end,
    ${pm("impact")} = case when save_postmortem.attrs ? 'impact' then save_postmortem.attrs ->> 'impact' else x.${pm("impact")} end,
    ${pm("rootCause")} = case when save_postmortem.attrs ? 'rootCause' then save_postmortem.attrs ->> 'rootCause' else x.${pm("rootCause")} end,
    ${pm("resolution")} = case when save_postmortem.attrs ? 'resolution' then save_postmortem.attrs ->> 'resolution' else x.${pm("resolution")} end,
    ${pm("actionItems")} = case when save_postmortem.attrs ? 'actionItems' then save_postmortem.attrs -> 'actionItems' else x.${pm("actionItems")} end,
    ${pm("updatedAt")} = now()
    where x.${pm("incident")} = v_row.${i("id")}
    returning * into v_post;
  return ${postmortemJson("v_post")};
end;
$$;
${userGrant(`${fn("save_postmortem")}(uuid, jsonb)`)}

-- Publishes a resolved incident's postmortem. A public incident's status page
-- then shows its summary.
create or replace function ${fn("publish_postmortem")}(incident_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${incidents}%rowtype;
  v_post ${postmortems}%rowtype;
begin
  select * into v_row from ${incidents} x where x.${i("id")} = publish_postmortem.incident_id;
  if not found then
    ${incidentNotFound}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, manage)} then
    ${forbidden("not allowed to publish postmortems")}
  end if;
  if v_row.${i("status")} <> 'resolved' then
    ${fail("INCIDENT_NOT_RESOLVED", "only a resolved incident's postmortem can be published", "55000")}
  end if;
  update ${postmortems} x set ${pm("status")} = 'published', ${pm("publishedAt")} = coalesce(x.${pm("publishedAt")}, now()), ${pm("updatedAt")} = now()
    where x.${pm("incident")} = v_row.${i("id")}
    returning * into v_post;
  if not found then
    ${fail("POSTMORTEM_NOT_FOUND", "the incident has no postmortem", "P0002")}
  end if;
  ${incidentRecord(
    "postmortem.published",
    `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'postmortemId', v_post.${pm("id")}, 'incidentId', v_row.${i("id")})`,
    `'published the postmortem of incident ' || v_row.${i("title")}`,
  )}
  return ${postmortemJson("v_post")};
end;
$$;
${userGrant(`${fn("publish_postmortem")}(uuid)`)}
`;
}
