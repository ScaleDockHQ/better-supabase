import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  canIn,
  fail,
  lockTable,
  schemaPreamble,
  serviceGrant,
  tenantIn,
  userGrant,
} from "../shared.ts";
import { subjectInTenant, subjectTenant } from "../subject-check-sql.ts";
import {
  type RegisteredSubject,
  registeredSubjects,
} from "../subject-registry.ts";
import { moduleOperations } from "./access-model.ts";

const CLOCK = [
  "organizationId",
  "clockId",
  "subjectType",
  "subjectId",
  "metric",
  "dueAt",
] as const;

const EVENTS: ModuleEvents = {
  "sla.warned": { subject: "sla-clocks", payload: [...CLOCK] },
  "sla.breached": { subject: "sla-clocks", payload: [...CLOCK] },
  "sla.completed": { subject: "sla-clocks", payload: [...CLOCK, "late"] },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [],
  options: ["businessHours", "subjects"],
  tables: {
    policies: {
      name: "sla_policies",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        name: "name",
        priority: "priority",
        firstResponse: "first_response_minutes",
        nextResponse: "next_response_minutes",
        resolution: "resolution_minutes",
        warnPercent: "warn_at_percent",
        businessHours: "business_hours",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    clocks: {
      name: "sla_clocks",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        policy: "policy_id",
        metric: "metric",
        startedAt: "started_at",
        dueAt: "due_at",
        pausedAt: "paused_at",
        pausedSeconds: "paused_seconds",
        warnedAt: "warned_at",
        breachedAt: "breached_at",
        metAt: "met_at",
        createdAt: "created_at",
      },
    },
  },
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;

interface BusinessHours {
  readonly timeZone: string;
  readonly start: string;
  readonly end: string;
  readonly days: readonly number[];
}

function businessHours(ctx: ModuleContext): BusinessHours {
  const raw = ctx.option("businessHours") ?? {};
  const where = "blocks.sla.options.businessHours";
  if (!isRecord(raw)) throw new TypeError(`${where} must be an object`);
  const timeZone = raw["timeZone"] ?? "UTC";
  const start = raw["start"] ?? "09:00";
  const end = raw["end"] ?? "17:00";
  const days = raw["days"] ?? [1, 2, 3, 4, 5];
  if (
    typeof timeZone !== "string" ||
    !/^[A-Za-z_]+(\/[A-Za-z_+-]+)*$/.test(timeZone)
  ) {
    throw new TypeError(
      `${where}.timeZone must be an IANA name such as Europe/Amsterdam`,
    );
  }
  if (
    typeof start !== "string" ||
    typeof end !== "string" ||
    !TIME.test(start) ||
    !TIME.test(end) ||
    end <= start
  ) {
    throw new TypeError(
      `${where}.start and end are HH:MM with end after start`,
    );
  }
  if (
    !Array.isArray(days) ||
    days.length === 0 ||
    days.some(
      (day) =>
        typeof day !== "number" || !Number.isInteger(day) || day < 1 || day > 7,
    )
  ) {
    throw new TypeError(
      `${where}.days lists ISO weekdays, 1 Monday to 7 Sunday`,
    );
  }
  return { timeZone, start, end, days: days.map(Number) };
}

/** A record type whose status column drives its clocks. */
interface SlaBinding {
  readonly subject: RegisteredSubject;
  readonly status: string;
  readonly priority?: string;
  /** Statuses that pause the clocks, such as waiting on the customer. */
  readonly pause: readonly string[];
  /** Statuses that resolve the record. */
  readonly resolve: readonly string[];
}

function bindings(ctx: ModuleContext): readonly SlaBinding[] {
  const raw = ctx.option("subjects") ?? {};
  if (!isRecord(raw)) {
    throw new TypeError("blocks.sla.options.subjects must be an object");
  }
  const registry = registeredSubjects(ctx.subjects);
  return Object.entries(raw).map(([type, entry]) => {
    const where = `blocks.sla.options.subjects.${type}`;
    const subject = registry.find((item) => item.type === type);
    if (subject?.tenant === undefined) {
      throw new TypeError(
        `${where}: register "${type}" with a tenant column in config.subjects first`,
      );
    }
    if (!isRecord(entry)) throw new TypeError(`${where} must be an object`);
    const status = entry["status"];
    const priority = entry["priority"];
    if (typeof status !== "string" || !COLUMN.test(status)) {
      throw new TypeError(`${where}.status must be a column name`);
    }
    if (
      priority !== undefined &&
      (typeof priority !== "string" || !COLUMN.test(priority))
    ) {
      throw new TypeError(`${where}.priority must be a column name`);
    }
    const list = (key: string): readonly string[] => {
      const value = entry[key] ?? [];
      if (
        !Array.isArray(value) ||
        value.some((item) => typeof item !== "string")
      ) {
        throw new TypeError(`${where}.${key} must be a list of statuses`);
      }
      return value.map(String);
    };
    return {
      subject,
      status,
      pause: list("pause"),
      resolve: list("resolve"),
      ...(typeof priority === "string" && { priority }),
    };
  });
}

const textArray = (items: readonly string[]): string =>
  `${sqlString(`{${items.map((item) => `"${item.replaceAll('"', '\\"')}"`).join(",")}}`)}::text[]`;

function bindingTrigger(
  binding: SlaBinding,
  fn: (name: string) => string,
): string {
  const type = binding.subject.type;
  const name = `bs_sla_${type}`;
  const status = sqlIdent(binding.status);
  const priority =
    binding.priority === undefined
      ? "null"
      : `new.${sqlIdent(binding.priority)}::text`;
  const id = `new.${binding.subject.id}::text`;
  const watched = [
    binding.status,
    ...(binding.priority === undefined ? [] : [binding.priority]),
  ]
    .map(sqlIdent)
    .join(", ");
  return `
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform ${fn("start_sla_clocks")}(${sqlString(type)}, ${id}, ${priority}, true);
    return null;
  end if;
  ${
    binding.priority === undefined
      ? ""
      : `if new.${sqlIdent(binding.priority)} is distinct from old.${sqlIdent(binding.priority)} then
    perform ${fn("start_sla_clocks")}(${sqlString(type)}, ${id}, ${priority}, true);
  end if;`
  }
  if new.${status} is distinct from old.${status} then
    if new.${status}::text = any (${textArray(binding.resolve)}) then
      perform ${fn("record_sla_event")}(${sqlString(type)}, ${id}, 'resolved');
    elsif old.${status}::text = any (${textArray(binding.resolve)}) then
      perform ${fn("record_sla_event")}(${sqlString(type)}, ${id}, 'reopened');
    end if;
    if new.${status}::text = any (${textArray(binding.pause)}) then
      perform ${fn("record_sla_event")}(${sqlString(type)}, ${id}, 'paused');
    elsif old.${status}::text = any (${textArray(binding.pause)}) then
      perform ${fn("record_sla_event")}(${sqlString(type)}, ${id}, 'resumed');
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists ${name} on ${binding.subject.qualified};
create trigger ${name} after insert or update of ${watched} on ${binding.subject.qualified}
for each row execute function better_supabase.${name}();`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const keys = moduleOperations("sla");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);
  const fn = (name: string): string => ctx.fn(name);
  const t = (table: string): string => ctx.table(table);
  const p = (column: string): string => ctx.col("policies", column);
  const k = (column: string): string => ctx.col("clocks", column);
  const hours = businessHours(ctx);
  const service = "(auth.role() = 'service_role')";
  const record = (type: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_clock.${k("tenant")}, 'clockId', v_clock.${k("id")}, 'subjectType', v_clock.${k("subjectType")}, 'subjectId', v_clock.${k("subjectId")}, 'metric', v_clock.${k("metric")}, 'dueAt', v_clock.${k("dueAt")}${extra})`,
      subject: `'sla-clocks/' || v_clock.${k("id")}::text`,
      tenant: `v_clock.${k("tenant")}::text`,
      audit: false,
    });
  const notify = (kind: string): string =>
    ctx.installed("notifications")
      ? ctx.notify(
          `jsonb_build_object(
      'type', ${sqlString(`sla.${kind}`)},
      'tenant', v_clock.${k("tenant")},
      'subject_type', v_clock.${k("subjectType")},
      'subject_id', v_clock.${k("subjectId")},
      'summary', v_clock.${k("metric")} || ' ' || ${sqlString(kind)},
      'priority', 'high',
      'key', ${sqlString(`sla.${kind}:`)} || v_clock.${k("id")}::text,
      'data', jsonb_build_object('clockId', v_clock.${k("id")}, 'metric', v_clock.${k("metric")}, 'dueAt', v_clock.${k("dueAt")})
    )`,
          { indent: "      " },
        )
      : "";
  const list = bindings(ctx);
  return `${schemaPreamble(ctx)}
-- Service levels on any record: response and resolution clocks from a
-- policy per record type and priority, in business hours, paused while the
-- record waits, with warnings and breaches recorded by a job.
${
  ctx.manages
    ? `create table if not exists ${t("policies")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("subjectType")} text not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("priority")} text,
  ${p("firstResponse")} integer check (${p("firstResponse")} > 0),
  ${p("nextResponse")} integer check (${p("nextResponse")} > 0),
  ${p("resolution")} integer check (${p("resolution")} > 0),
  ${p("warnPercent")} smallint not null default 80 check (${p("warnPercent")} between 1 and 99),
  ${p("businessHours")} boolean not null default false,
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now()
);
create unique index if not exists sla_policies_match_idx on ${t("policies")} (${p("tenant")}, ${p("subjectType")}, coalesce(${p("priority")}, '')) where ${p("archivedAt")} is null;
${lockTable(t("policies"), { read: true })}
drop policy if exists sla_policies_read on ${t("policies")};
create policy sla_policies_read on ${t("policies")} for select to authenticated
using (${tenantIn(p("tenant"), read)});

create table if not exists ${t("clocks")} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("subjectType")} text not null,
  ${k("subjectId")} text not null,
  ${k("policy")} uuid references ${t("policies")} (${p("id")}) on delete set null,
  ${k("metric")} text not null check (${k("metric")} in ('first_response', 'next_response', 'resolution')),
  ${k("startedAt")} timestamptz not null,
  ${k("dueAt")} timestamptz not null,
  ${k("pausedAt")} timestamptz,
  ${k("pausedSeconds")} integer not null default 0,
  ${k("warnedAt")} timestamptz,
  ${k("breachedAt")} timestamptz,
  ${k("metAt")} timestamptz,
  ${k("createdAt")} timestamptz not null default now()
);
create unique index if not exists sla_clocks_open_idx on ${t("clocks")} (${k("subjectType")}, ${k("subjectId")}, ${k("metric")}) where ${k("metAt")} is null;
create index if not exists sla_clocks_due_idx on ${t("clocks")} (${k("dueAt")}) where ${k("metAt")} is null and ${k("pausedAt")} is null;
create index if not exists sla_clocks_policy_idx on ${t("clocks")} (${k("policy")});
${lockTable(t("clocks"), { read: true })}
drop policy if exists sla_clocks_read on ${t("clocks")};
create policy sla_clocks_read on ${t("clocks")} for select to authenticated
using (${tenantIn(k("tenant"), read)} and ${ctx.of("subjects").fn("can_subject")}(${k("subjectType")}, ${k("subjectId")}, 'read'));
`
    : ""
}
-- The time minutes of working time after start: business hours on the
-- configured weekdays in the configured time zone, or plain minutes.
create or replace function ${fn("sla_due_at")}(start timestamptz, minutes integer, business boolean)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_left integer := sla_due_at.minutes;
  v_local timestamp := sla_due_at.start at time zone ${sqlString(hours.timeZone)};
  v_open timestamp;
  v_close timestamp;
  v_take integer;
begin
  if not sla_due_at.business then
    return sla_due_at.start + make_interval(mins => sla_due_at.minutes);
  end if;
  for v_day in 0..400 loop
    v_open := date_trunc('day', v_local) + ${sqlString(hours.start)}::time;
    v_close := date_trunc('day', v_local) + ${sqlString(hours.end)}::time;
    if extract(isodow from v_local)::integer = any (${sqlString(`{${hours.days.join(",")}}`)}::integer[]) and v_local < v_close then
      v_local := greatest(v_local, v_open);
      v_take := least(v_left, (extract(epoch from v_close - v_local) / 60)::integer);
      v_local := v_local + make_interval(mins => v_take);
      v_left := v_left - v_take;
      if v_left <= 0 then
        return v_local at time zone ${sqlString(hours.timeZone)};
      end if;
    end if;
    v_local := date_trunc('day', v_local) + interval '1 day';
  end loop;
  ${fail("SLA_HOURS_INVALID", "no business hours within 400 days", "22023")}
end;
$$;
revoke execute on function ${fn("sla_due_at")}(timestamptz, integer, boolean) from public, anon;
grant execute on function ${fn("sla_due_at")}(timestamptz, integer, boolean) to authenticated, service_role;

-- Creates or changes a policy: name, subjectType, priority (null for every
-- priority), firstResponseMinutes, nextResponseMinutes, resolutionMinutes,
-- warnAtPercent, businessHours, archived.
create or replace function ${fn("save_sla_policy")}(tenant ${ctx.idType}, policy uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_sla_policy.policy;
begin
  if not (${service} or ${canIn("save_sla_policy.tenant", manage)}) then
    ${fail("SLA_FORBIDDEN", "not allowed to manage service levels")}
  end if;
  begin
    if v_id is null then
      insert into ${t("policies")} (${p("tenant")}, ${p("subjectType")}, ${p("name")}, ${p("priority")}, ${p("firstResponse")}, ${p("nextResponse")}, ${p("resolution")}, ${p("warnPercent")}, ${p("businessHours")})
      values (save_sla_policy.tenant, save_sla_policy.attrs ->> 'subjectType', save_sla_policy.attrs ->> 'name', save_sla_policy.attrs ->> 'priority',
        (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer, (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer,
        (save_sla_policy.attrs ->> 'resolutionMinutes')::integer, coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, 80),
        coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, false))
      returning ${p("id")} into v_id;
    else
      update ${t("policies")} x set
        ${p("name")} = coalesce(save_sla_policy.attrs ->> 'name', x.${p("name")}),
        ${p("priority")} = case when save_sla_policy.attrs ? 'priority' then save_sla_policy.attrs ->> 'priority' else x.${p("priority")} end,
        ${p("firstResponse")} = case when save_sla_policy.attrs ? 'firstResponseMinutes' then (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer else x.${p("firstResponse")} end,
        ${p("nextResponse")} = case when save_sla_policy.attrs ? 'nextResponseMinutes' then (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer else x.${p("nextResponse")} end,
        ${p("resolution")} = case when save_sla_policy.attrs ? 'resolutionMinutes' then (save_sla_policy.attrs ->> 'resolutionMinutes')::integer else x.${p("resolution")} end,
        ${p("warnPercent")} = coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, x.${p("warnPercent")}),
        ${p("businessHours")} = coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, x.${p("businessHours")}),
        ${p("archivedAt")} = case when coalesce((save_sla_policy.attrs ->> 'archived')::boolean, false) then coalesce(x.${p("archivedAt")}, now()) else x.${p("archivedAt")} end,
        ${p("updatedAt")} = now()
      where x.${p("id")} = v_id and x.${p("tenant")} = save_sla_policy.tenant;
      if not found then
        ${fail("SLA_POLICY_NOT_FOUND", "policy not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("SLA_POLICY_TAKEN", "another active policy covers this record type and priority", "23505")}
  when check_violation or not_null_violation or invalid_text_representation then
    ${fail("SLA_POLICY_INVALID", "a policy needs a name, a record type and positive minutes", "22023")}
  end;
  return (select to_jsonb(x) from ${t("policies")} x where x.${p("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_sla_policy")}(${ctx.idType}, uuid, jsonb)`)}

-- Starts a record's clocks from the policy for its type and priority (the
-- exact priority first, then the policy without one). Starting again, as
-- when the priority changes, recomputes the due times of the open clocks
-- from when they started.
create or replace function ${fn("start_sla_clocks")}(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := ${subjectTenant(ctx, "start_sla_clocks.subject_type", "start_sla_clocks.subject_id")};
  v_policy ${t("policies")};
  v_metric text;
  v_minutes integer;
begin
  if v_tenant is null then
    ${fail("SLA_SUBJECT_INVALID", "unknown record", "P0002")}
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not (${service} or ${subjectInTenant(ctx, "start_sla_clocks.subject_type", "start_sla_clocks.subject_id", "v_tenant")}) then
    ${fail("SLA_FORBIDDEN", "not allowed to start clocks on this record")}
  end if;
  select * into v_policy from ${t("policies")} x
  where x.${p("tenant")}::text = v_tenant and x.${p("subjectType")} = start_sla_clocks.subject_type and x.${p("archivedAt")} is null
    and (x.${p("priority")} = start_sla_clocks.priority or x.${p("priority")} is null)
  order by x.${p("priority")} nulls last
  limit 1;
  if v_policy.${p("id")} is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy.${p("firstResponse")} else v_policy.${p("resolution")} end;
    if v_minutes is null then
      continue;
    end if;
    update ${t("clocks")} x set ${k("policy")} = v_policy.${p("id")},
      ${k("dueAt")} = ${fn("sla_due_at")}(x.${k("startedAt")}, v_minutes, v_policy.${p("businessHours")}) + make_interval(secs => x.${k("pausedSeconds")})
    where x.${k("subjectType")} = start_sla_clocks.subject_type and x.${k("subjectId")} = start_sla_clocks.subject_id
      and x.${k("metric")} = v_metric and x.${k("metAt")} is null;
    if not found and not exists (
      select 1 from ${t("clocks")} x where x.${k("subjectType")} = start_sla_clocks.subject_type and x.${k("subjectId")} = start_sla_clocks.subject_id and x.${k("metric")} = v_metric
    ) then
      insert into ${t("clocks")} (${k("tenant")}, ${k("subjectType")}, ${k("subjectId")}, ${k("policy")}, ${k("metric")}, ${k("startedAt")}, ${k("dueAt")})
      values (v_policy.${p("tenant")}, start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy.${p("id")}, v_metric, now(),
        ${fn("sla_due_at")}(now(), v_minutes, v_policy.${p("businessHours")}));
    end if;
  end loop;
  return ${fn("sla_clocks_of")}(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$$;
${userGrant(`${fn("start_sla_clocks")}(text, text, text, boolean)`)}

-- Moves a record's clocks: responded meets the response clock and starts
-- the next-response clock; resolved meets every open clock; reopened starts
-- a new resolution clock; paused and resumed stop and restart them, moving
-- the due times by the pause.
create or replace function ${fn("record_sla_event")}(subject_type text, subject_id text, event text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := ${subjectTenant(ctx, "record_sla_event.subject_type", "record_sla_event.subject_id")};
  v_clock ${t("clocks")};
  v_policy ${t("policies")};
  v_meet text[];
begin
  if v_tenant is null then
    ${fail("SLA_SUBJECT_INVALID", "unknown record", "P0002")}
  end if;
  if pg_trigger_depth() = 0 and not (${service} or ${subjectInTenant(ctx, "record_sla_event.subject_type", "record_sla_event.subject_id", "v_tenant")}) then
    ${fail("SLA_FORBIDDEN", "not allowed to move clocks on this record")}
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update ${t("clocks")} x set ${k("pausedAt")} = now()
      where x.${k("subjectType")} = record_sla_event.subject_type and x.${k("subjectId")} = record_sla_event.subject_id
        and x.${k("metAt")} is null and x.${k("pausedAt")} is null;
      return ${fn("sla_clocks_of")}(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update ${t("clocks")} x set
        ${k("dueAt")} = x.${k("dueAt")} + (now() - x.${k("pausedAt")}),
        ${k("pausedSeconds")} = x.${k("pausedSeconds")} + extract(epoch from now() - x.${k("pausedAt")})::integer,
        ${k("pausedAt")} = null
      where x.${k("subjectType")} = record_sla_event.subject_type and x.${k("subjectId")} = record_sla_event.subject_id
        and x.${k("metAt")} is null and x.${k("pausedAt")} is not null;
      return ${fn("sla_clocks_of")}(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      ${fail("SLA_EVENT_INVALID", "event is responded, resolved, reopened, paused or resumed", "22023")}
  end case;
  for v_clock in
    update ${t("clocks")} x set ${k("metAt")} = now(), ${k("pausedAt")} = null
    where x.${k("subjectType")} = record_sla_event.subject_type and x.${k("subjectId")} = record_sla_event.subject_id
      and x.${k("metAt")} is null and x.${k("metric")} = any (v_meet)
    returning *
  loop
    ${record("sla.completed", `, 'late', v_clock.${k("metAt")} > v_clock.${k("dueAt")}`)}
  end loop;
  select x.* into v_policy from ${t("clocks")} c join ${t("policies")} x on x.${p("id")} = c.${k("policy")}
  where c.${k("subjectType")} = record_sla_event.subject_type and c.${k("subjectId")} = record_sla_event.subject_id
  order by c.${k("createdAt")} desc limit 1;
  if v_policy.${p("id")} is not null then
    if record_sla_event.event = 'responded' and v_policy.${p("nextResponse")} is not null
      and exists (select 1 from ${t("clocks")} x where x.${k("subjectType")} = record_sla_event.subject_type and x.${k("subjectId")} = record_sla_event.subject_id and x.${k("metric")} = 'resolution' and x.${k("metAt")} is null) then
      insert into ${t("clocks")} (${k("tenant")}, ${k("subjectType")}, ${k("subjectId")}, ${k("policy")}, ${k("metric")}, ${k("startedAt")}, ${k("dueAt")})
      values (v_policy.${p("tenant")}, record_sla_event.subject_type, record_sla_event.subject_id, v_policy.${p("id")}, 'next_response', now(),
        ${fn("sla_due_at")}(now(), v_policy.${p("nextResponse")}, v_policy.${p("businessHours")}))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy.${p("resolution")} is not null then
      insert into ${t("clocks")} (${k("tenant")}, ${k("subjectType")}, ${k("subjectId")}, ${k("policy")}, ${k("metric")}, ${k("startedAt")}, ${k("dueAt")})
      values (v_policy.${p("tenant")}, record_sla_event.subject_type, record_sla_event.subject_id, v_policy.${p("id")}, 'resolution', now(),
        ${fn("sla_due_at")}(now(), v_policy.${p("resolution")}, v_policy.${p("businessHours")}))
      on conflict do nothing;
    end if;
  end if;
  return ${fn("sla_clocks_of")}(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$$;
${userGrant(`${fn("record_sla_event")}(text, text, text)`)}

-- A record's clocks the caller can see, newest first, with their state:
-- running, paused, met, breached; and the seconds left.
create or replace function ${fn("sla_clocks_of")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
    'state', case
      when x.${k("metAt")} is not null then 'met'
      when x.${k("pausedAt")} is not null then 'paused'
      when x.${k("dueAt")} < now() then 'breached'
      else 'running' end,
    'secondsLeft', case when x.${k("metAt")} is null then extract(epoch from x.${k("dueAt")} - coalesce(x.${k("pausedAt")}, now()))::integer end
  ) order by x.${k("createdAt")} desc, x.${k("metric")}), '[]'::jsonb)
  from ${t("clocks")} x
  where x.${k("subjectType")} = sla_clocks_of.subject_type and x.${k("subjectId")} = sla_clocks_of.subject_id
$$;
${userGrant(`${fn("sla_clocks_of")}(text, text)`)}

-- Records warnings and breaches of running clocks and notifies the record's
-- watchers. Run it every minute or so from a job. Returns how many changed.
create or replace function ${fn("check_sla_clocks")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clock ${t("clocks")};
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update ${t("clocks")} x set ${k("breachedAt")} = now()
    where x.${k("metAt")} is null and x.${k("pausedAt")} is null and x.${k("breachedAt")} is null and x.${k("dueAt")} < now()
    returning *
  loop
    ${record("sla.breached")}
    ${notify("breached")}
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update ${t("clocks")} x set ${k("warnedAt")} = now()
    from ${t("policies")} y
    where y.${p("id")} = x.${k("policy")} and x.${k("metAt")} is null and x.${k("pausedAt")} is null and x.${k("warnedAt")} is null
      and x.${k("breachedAt")} is null
      and now() >= x.${k("startedAt")} + (x.${k("dueAt")} - x.${k("startedAt")}) * y.${p("warnPercent")} / 100.0
    returning x.*
  loop
    ${record("sla.warned")}
    ${notify("warned")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("check_sla_clocks")}()`)}
${list.map((binding) => bindingTrigger(binding, fn)).join("\n")}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "sla_due_at",
      args: ["timestamptz", "integer", "boolean"],
      returns: "timestamptz",
    },
    {
      name: "save_sla_policy",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "start_sla_clocks",
      args: ["text", "text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "record_sla_event",
      args: ["text", "text", "text"],
      returns: "jsonb",
    },
    { name: "sla_clocks_of", args: ["text", "text"], returns: "jsonb" },
    { name: "check_sla_clocks", args: [], returns: "integer" },
  ];
}

export const SLA: ModuleDefinition = {
  name: "sla",
  title: "Service levels",
  description:
    "Service levels on any registered record: first response, next response and resolution clocks from a policy per type and priority, business hours, pauses while the record waits, and warnings and breaches a job records.",
  requires: ["tenant", "access", "subjects"],
  integrates: ["outbox", "notifications"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
