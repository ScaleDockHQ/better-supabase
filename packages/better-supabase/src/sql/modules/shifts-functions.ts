import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  fail,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import {
  assignmentRecord,
  notifyShift,
  SHIFT_RESERVED,
  shiftJson,
  shiftRecord,
  shiftTimeZone,
  teamType,
  templateJson,
} from "./shifts-shared.ts";

/** The longest range generate_shifts covers, in days. */
const GENERATE_DAYS = 92;

/**
 * The checks that `team`, `location` and `qualifications` (SQL expressions)
 * belong to `tenant`, for the shift or template table `logical`.
 */
function shiftRefChecks(
  ctx: BlockSqlContext,
  options: {
    readonly logical: string;
    readonly tenant: string;
    readonly team: string;
    readonly location: string;
    readonly qualifications: string;
  },
): string {
  const invalid = (message: string): string =>
    fail("SHIFT_INVALID", message, "22023");

  const teams = ctx.of("teams");
  const tc = (column: string): string => teams.col("teams", column);

  const team = `if ${options.team} is not null and not exists (
    select 1 from ${teams.table("teams")} o where o.${tc("id")} = ${options.team} and o.${tc("tenant")} = ${options.tenant}
  ) then
    ${invalid("the team isn't in this organization")}
  end if;`;

  const assets = ctx.installed("assets") ? ctx.of("assets") : undefined;

  const location =
    assets === undefined || !ctx.has(options.logical, "location")
      ? `if ${options.location} is not null then
    ${invalid(assets === undefined ? "location_id needs the assets block" : "the table has no location column")}
  end if;`
      : `if ${options.location} is not null and not exists (
    select 1 from ${assets.table("assets")} o where o.${assets.col("assets", "id")} = ${options.location} and o.${assets.col("assets", "tenant")} = ${options.tenant}
  ) then
    ${invalid("the location isn't an asset in this organization")}
  end if;`;

  const qualifications = ctx.installed("qualifications")
    ? ctx.of("qualifications")
    : undefined;

  const required =
    qualifications === undefined
      ? `if cardinality(coalesce(${options.qualifications}, '{}')) > 0 then
    ${invalid("required_qualifications needs the qualifications block")}
  end if;`
      : `if exists (
    select 1 from unnest(coalesce(${options.qualifications}, '{}')) k
    where not exists (
      select 1 from ${qualifications.table("types")} o
      where o.${qualifications.col("types", "tenant")} = ${options.tenant} and o.${qualifications.col("types", "key")} = k and o.${qualifications.col("types", "archivedAt")} is null
    )
  ) then
    ${invalid("every required qualification is a qualification type key of this organization")}
  end if;`;

  return `${team}
  ${location}
  ${required}`;
}

/** The template, generate, save, cancel and publish functions. */
export function shiftFunctions(ctx: BlockSqlContext): string {
  const templates = ctx.table("templates");
  const shifts = ctx.table("shifts");
  const assignments = ctx.table("assignments");
  const t = (column: string): string => ctx.col("templates", column);
  const s = (column: string): string => ctx.col("shifts", column);
  const a = (column: string): string => ctx.col("assignments", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("shifts");
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);
  const extras = ctx.extraColumns("shifts", SHIFT_RESERVED);
  const extra = extraFieldsArg(extras);
  const zone = sqlString(shiftTimeZone(ctx));
  const team = teamType(ctx);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const insertCol = (table: string, column: string): string =>
    has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    has(table, column) ? `, ${value}` : "";

  const touch = (table: string): string =>
    has(table, "updatedAt") ? `, ${ctx.col(table, "updatedAt")} = now()` : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("SHIFT_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("SHIFT_INVALID", message, "22023");

  const shiftNotFound = fail("SHIFT_NOT_FOUND", "shift not found", "P0002");

  const templateNotFound = fail(
    "SHIFT_TEMPLATE_NOT_FOUND",
    "shift template not found",
    "P0002",
  );

  const templateSets = [
    `${t("name")} = v_name`,
    `${t("team")} = save_shift_template.team_id`,
    has("templates", "location")
      ? `${t("location")} = save_shift_template.location_id`
      : "",
    `${t("startsTime")} = save_shift_template.starts_time`,
    `${t("endsTime")} = save_shift_template.ends_time`,
    `${t("breakMinutes")} = coalesce(save_shift_template.break_minutes, 0)`,
    `${t("headcount")} = coalesce(save_shift_template.headcount, 1)`,
    `${t("requiredQualifications")} = v_required`,
    `${t("weekdays")} = v_weekdays`,
    has("templates", "updatedAt") ? `${t("updatedAt")} = now()` : "",
  ]
    .filter((set) => set !== "")
    .join(",\n      ");

  const shiftSets = [
    `${s("startsAt")} = save_shift.starts_at`,
    `${s("endsAt")} = save_shift.ends_at`,
    `${s("team")} = save_shift.team_id`,
    has("shifts", "location")
      ? `${s("location")} = save_shift.location_id`
      : "",
    `${s("breakMinutes")} = coalesce(save_shift.break_minutes, 0)`,
    `${s("headcount")} = coalesce(save_shift.headcount, 1)`,
    `${s("requiredQualifications")} = v_required`,
    has("shifts", "note")
      ? `${s("note")} = nullif(trim(save_shift.note), '')`
      : "",
    has("shifts", "updatedAt") ? `${s("updatedAt")} = now()` : "",
  ]
    .filter((set) => set !== "")
    .join(",\n      ");

  const required = (value: string): string =>
    `array(select distinct k from unnest(coalesce(${value}, '{}')) k where k is not null order by k)`;

  const shiftEvent = (event: string, extraPairs: string, summary: string) =>
    shiftRecord(ctx, event, "v_row", extraPairs, summary);

  const assigned = `coalesce((select jsonb_agg(x.${a("user")}) from ${assignments} x where x.${a("shift")} = v_row.${s("id")} and x.${a("status")} = 'assigned'), '[]'::jsonb)`;

  const notifyPublished = notifyShift(ctx, {
    type: "shift.published",
    tenant: `v_row.${s("tenant")}`,
    shift: `v_row.${s("id")}`,
    recipients: assigned,
    summary: "'Your shift is published'",
    key: `'shift.published:' || v_row.${s("id")}::text`,
    data: `jsonb_build_object('startsAt', v_row.${s("startsAt")}, 'endsAt', v_row.${s("endsAt")})`,
  });

  const notifyCanceled = notifyShift(ctx, {
    type: "shift.cancelled",
    tenant: `v_row.${s("tenant")}`,
    shift: `v_row.${s("id")}`,
    recipients: "v_users",
    summary: "'Your shift is canceled'",
    key: `'shift.cancelled:' || v_row.${s("id")}::text`,
    data: `jsonb_build_object('startsAt', v_row.${s("startsAt")}, 'endsAt', v_row.${s("endsAt")})`,
  });

  const claims = ctx.installed("notifications") ? "\n  v_claims text;" : "";

  const refChecks = (logical: string, fnName: string): string =>
    shiftRefChecks(ctx, {
      logical,
      tenant: `${fnName}.tenant`,
      team: `${fnName}.team_id`,
      location: `${fnName}.location_id`,
      qualifications: "v_required",
    });

  return `
-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function ${fn("save_shift_template")}(tenant ${idType}, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id ${team} default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${templates}%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := ${required("save_shift_template.required_qualifications")};
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not ${allowed("save_shift_template.tenant", write)} then
    ${forbidden("not allowed to plan shifts")}
  end if;
  if v_name is null or length(v_name) > 200 then
    ${invalid("a shift template needs a name of at most 200 characters")}
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    ${invalid("a shift template needs a start and an end time")}
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    ${invalid("weekdays are 1 (Monday) to 7 (Sunday)")}
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    ${invalid("break_minutes is between 0 and 720")}
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    ${invalid("headcount is between 1 and 500")}
  end if;
  ${refChecks("templates", "save_shift_template")}
  if save_shift_template.template_id is null then
    insert into ${templates} (${t("tenant")}, ${t("name")}, ${t("team")}${insertCol("templates", "location")}, ${t("startsTime")}, ${t("endsTime")}, ${t("breakMinutes")}, ${t("headcount")}, ${t("requiredQualifications")}, ${t("weekdays")})
    values (save_shift_template.tenant, v_name, save_shift_template.team_id${insertVal("templates", "location", "save_shift_template.location_id")}, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update ${templates} x set
      ${templateSets},
      ${t("archivedAt")} = null
    where x.${t("id")} = save_shift_template.template_id and x.${t("tenant")} = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      ${templateNotFound}
    end if;
  end if;
  return ${templateJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("save_shift_template")}(${idType}, text, time, time, integer[], ${team}, uuid, integer, integer, text[], uuid)`)}

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function ${fn("archive_shift_template")}(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${templates}%rowtype;
begin
  select * into v_row from ${templates} x where x.${t("id")} = archive_shift_template.template_id;
  if not found then
    ${templateNotFound}
  end if;
  if not ${allowed(`v_row.${t("tenant")}`, write)} then
    ${forbidden("not allowed to plan shifts")}
  end if;
  update ${templates} x set ${t("archivedAt")} = coalesce(x.${t("archivedAt")}, now())${touch("templates")}
  where x.${t("id")} = v_row.${t("id")}
  returning x.* into v_row;
  return ${templateJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("archive_shift_template")}(uuid)`)}

create or replace function ${fn("list_shift_templates")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${templateJson(ctx, "x")} order by x.${t("name")}, x.${t("id")}), '[]'::jsonb)
  from ${templates} x
  where x.${t("tenant")} = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x.${t("archivedAt")} is null)
$$;
${userGrant(`${fn("list_shift_templates")}(${idType}, boolean)`)}

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most ${String(GENERATE_DAYS)} days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function ${fn("generate_shifts")}(tenant ${idType}, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template ${templates}%rowtype;
  v_row ${shifts}%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not ${allowed("generate_shifts.tenant", write)} then
    ${forbidden("not allowed to plan shifts")}
  end if;
  select * into v_template from ${templates} x
  where x.${t("id")} = generate_shifts.template_id and x.${t("tenant")} = generate_shifts.tenant and x.${t("archivedAt")} is null;
  if not found then
    ${templateNotFound}
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    ${invalid("until_date is on or after from_date")}
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= ${String(GENERATE_DAYS)} then
    ${invalid(`generate_shifts covers at most ${String(GENERATE_DAYS)} days`)}
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template.${t("weekdays")}));
    v_starts := (v_day + v_template.${t("startsTime")}) at time zone ${zone};
    v_ends := (v_day + v_template.${t("endsTime")} + case when v_template.${t("endsTime")} <= v_template.${t("startsTime")} then interval '1 day' else interval '0' end) at time zone ${zone};
    continue when exists (
      select 1 from ${shifts} x
      where x.${s("tenant")} = v_template.${t("tenant")} and x.${s("template")} = v_template.${t("id")} and x.${s("startsAt")} = v_starts
    );
    insert into ${shifts} (${s("tenant")}, ${s("template")}, ${s("team")}${insertCol("shifts", "location")}, ${s("startsAt")}, ${s("endsAt")}, ${s("breakMinutes")}, ${s("headcount")}, ${s("requiredQualifications")}${insertCol("shifts", "createdBy")})
    values (v_template.${t("tenant")}, v_template.${t("id")}, v_template.${t("team")}${insertVal("shifts", "location", has("templates", "location") ? `v_template.${t("location")}` : "null")}, v_starts, v_ends, v_template.${t("breakMinutes")}, v_template.${t("headcount")}, v_template.${t("requiredQualifications")}${insertVal("shifts", "createdBy", "(select auth.uid())")})
    returning * into v_row;
    ${shiftEvent("shift.created", `, 'status', v_row.${s("status")}`, "Shift created")}
    v_created := v_created || jsonb_build_array(${shiftJson(ctx, "v_row")});
  end loop;
  return v_created;
end;
$$;
${userGrant(`${fn("generate_shifts")}(${idType}, uuid, date, date)`)}

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
${extra.drop(fn("save_shift"), `${idType}, timestamptz, timestamptz, ${team}, uuid, integer, integer, text[], text, uuid`)}
create or replace function ${fn("save_shift")}(tenant ${idType}, starts_at timestamptz, ends_at timestamptz, team_id ${team} default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${shifts}%rowtype;
  v_required text[] := ${required("save_shift.required_qualifications")};
begin
  if not ${allowed("save_shift.tenant", write)} then
    ${forbidden("not allowed to plan shifts")}
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    ${invalid("a shift ends after it starts")}
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    ${invalid("a shift lasts at most 24 hours")}
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    ${invalid("break_minutes is between 0 and 720")}
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    ${invalid("headcount is between 1 and 500")}
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    ${invalid("a note is at most 2000 characters")}
  end if;
  ${refChecks("shifts", "save_shift")}
  ${ctx.hook("before_shift_save", [
    [idType, "save_shift.tenant"],
    ["uuid", "save_shift.shift_id"],
  ])}
  if save_shift.shift_id is null then
    insert into ${shifts} (${s("tenant")}, ${s("team")}${insertCol("shifts", "location")}, ${s("startsAt")}, ${s("endsAt")}, ${s("breakMinutes")}, ${s("headcount")}, ${s("requiredQualifications")}${insertCol("shifts", "note")}${insertCol("shifts", "createdBy")})
    values (save_shift.tenant, save_shift.team_id${insertVal("shifts", "location", "save_shift.location_id")}, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required${insertVal("shifts", "note", "nullif(trim(save_shift.note), '')")}${insertVal("shifts", "createdBy", "(select auth.uid())")})
    returning * into v_row;${writeExtraColumns(shifts, extras, "save_shift.fields", `x.${s("id")} = v_row.${s("id")}`, "v_row")}
    ${shiftEvent("shift.created", `, 'status', v_row.${s("status")}`, "Shift created")}
  else
    select * into v_row from ${shifts} x
    where x.${s("id")} = save_shift.shift_id and x.${s("tenant")} = save_shift.tenant
    for update;
    if not found then
      ${shiftNotFound}
    end if;
    if v_row.${s("status")} = 'canceled' then
      ${fail("SHIFT_CANCELED", "the shift is canceled", "55000")}
    end if;
    update ${shifts} x set
      ${shiftSets}
    where x.${s("id")} = v_row.${s("id")}
    returning x.* into v_row;${writeExtraColumns(shifts, extras, "save_shift.fields", `x.${s("id")} = v_row.${s("id")}`, "v_row")}
    begin
      update ${assignments} x set ${a("startsAt")} = v_row.${s("startsAt")}, ${a("endsAt")} = v_row.${s("endsAt")}${touch("assignments")}
      where x.${a("shift")} = v_row.${s("id")} and (x.${a("startsAt")} <> v_row.${s("startsAt")} or x.${a("endsAt")} <> v_row.${s("endsAt")});
    exception when exclusion_violation then
      ${fail("SHIFT_ASSIGNMENT_OVERLAP", "an assigned member has another shift at the new time", "23P01")}
    end;
  end if;
  ${ctx.hook("after_shift_save", [["uuid", `v_row.${s("id")}`]])}
  return ${shiftJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("save_shift")}(${idType}, timestamptz, timestamptz, ${team}, uuid, integer, integer, text[], text, uuid${extra.type})`)}

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function ${fn("cancel_shift")}(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${shifts}%rowtype;
  v_assignment ${assignments}%rowtype;
  v_users jsonb := '[]'::jsonb;${claims}
begin
  select * into v_row from ${shifts} x where x.${s("id")} = cancel_shift.shift_id for update;
  if not found then
    ${shiftNotFound}
  end if;
  if not ${allowed(`v_row.${s("tenant")}`, manage)} then
    ${forbidden("not allowed to cancel shifts")}
  end if;
  if v_row.${s("status")} <> 'canceled' then
    ${ctx.hook("before_shift_cancel", [["uuid", `v_row.${s("id")}`]])}
    v_users := ${assigned};
    update ${shifts} x set ${s("status")} = 'canceled', ${s("canceledAt")} = now()${touch("shifts")}
    where x.${s("id")} = v_row.${s("id")}
    returning x.* into v_row;
    for v_assignment in
      update ${assignments} x set ${a("status")} = 'released'${touch("assignments")}
      where x.${a("shift")} = v_row.${s("id")} and x.${a("status")} <> 'released'
      returning x.*
    loop
      ${assignmentRecord(ctx, "shift_assignment.released", "v_assignment", ", 'reason', 'shift_canceled'", "Shift assignment released")}
    end loop;
    ${shiftEvent("shift.cancelled", ", 'reason', nullif(trim(cancel_shift.reason), '')", "Shift canceled")}
    if jsonb_array_length(v_users) > 0 then
      ${notifyCanceled}
    end if;
    ${ctx.hook("after_shift_cancel", [["uuid", `v_row.${s("id")}`]])}
  end if;
  return ${shiftJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("cancel_shift")}(uuid, text)`)}

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function ${fn("publish_shifts")}(tenant ${idType}, from_date date, until_date date, team_id ${team} default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${shifts}%rowtype;
  v_count integer := 0;${claims}
begin
  if not ${allowed("publish_shifts.tenant", manage)} then
    ${forbidden("not allowed to publish shifts")}
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    ${invalid("until_date is on or after from_date")}
  end if;
  for v_row in
    update ${shifts} x set ${s("status")} = 'published', ${s("publishedAt")} = now()${touch("shifts")}
    where x.${s("tenant")} = publish_shifts.tenant
      and x.${s("status")} = 'draft'
      and x.${s("startsAt")} >= publish_shifts.from_date::timestamp at time zone ${zone}
      and x.${s("startsAt")} < (publish_shifts.until_date + 1)::timestamp at time zone ${zone}
      and (publish_shifts.team_id is null or x.${s("team")} = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    ${shiftEvent("shift.published", "", "Shift published")}
    if jsonb_array_length(${assigned}) > 0 then
      ${notifyPublished}
    end if;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("publish_shifts")}(${idType}, date, date, ${team})`)}
`;
}
