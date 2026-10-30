import type { StateMachineEvents } from "../../blocks/state-machine/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Machine } from "./state-machine-options.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { asColumnType } from "../column-type.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  pageSize,
  quotedTable,
  readLine,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  transitionActorSql,
} from "../shared.ts";
import {
  LIFECYCLE_INTERNAL,
  lifecycleWorkflowSql,
  WORKFLOW_DECLARE,
  workflowCheck,
  workflowInsert,
  workflowState,
} from "./state-machine-lifecycle.ts";
import { ACTOR_FIELDS, machines } from "./state-machine-options.ts";

const SUBJECT = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: BlockSqlEvents<StateMachineEvents> = {
  "status.changed": {
    subject: "statuses",
    payload: [...SUBJECT, "from", "to"],
  },
  "status.paused": {
    subject: "statuses",
    payload: [...SUBJECT, "until", "reason"],
  },
  "status.resumed": { subject: "statuses", payload: [...SUBJECT] },
  "status.flagged": {
    subject: "statuses",
    payload: [...SUBJECT, "flag", "enabled"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: ["before_status_transition", "after_status_transition"],
  options: ["machines"],
  tables: {
    history: {
      name: "status_history",
      app: {},
      lifecycle: { tenant: "tenant", user: "actor", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        fromStatus: "from_status",
        toStatus: "to_status",
        actor: "actor_user_id",
        actorName: "actor_name",
        actorEmail: "actor_email",
        ip: "ip_address",
        userAgent: "user_agent",
        reason: "reason",
        createdAt: "created_at",
      },
      optional: ["actorName", "actorEmail", "ip", "userAgent"],
      typed: ["fromStatus", "toStatus"],
    },
    stages: {
      name: "status_stages",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        label: "label",
        outcome: "outcome",
        display: "display",
        clearedAt: "cleared_at",
        createdAt: "created_at",
      },
      typed: ["label"],
    },
    lifecycles: {
      name: "subject_lifecycles",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        version: "version",
        flags: "flags",
        pausedAt: "paused_at",
        pausedUntil: "paused_until",
        pauseReason: "pause_reason",
        pausedBy: "paused_by_user_id",
        workflowVersion: "workflow_version_id",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["workflowVersion"],
    },
  },
};

/**
 * The setting `pause_lifecycle`, `resume_lifecycle` and `set_lifecycle_flag`
 * pass to the trigger.
 */
const OP_SETTING = "better_supabase.lifecycle_op";

/** Set by the trigger when a lifecycle call changed the row. */
const CHANGED_SETTING = "better_supabase.lifecycle_changed";

/** The actor `transition()` passes to the trigger: name, email, ip, userAgent. */
const ACTOR_SETTING = "better_supabase.transition_actor";

const REASON =
  "nullif(current_setting('better_supabase.transition_reason', true), '')";

/**
 * The acting user: the signed-in user, else the actor's `id`, which the service
 * role passes for the user it acts for.
 */
const ACTOR_ID = `coalesce(auth.uid(), nullif(nullif(current_setting('${ACTOR_SETTING}', true), '')::jsonb ->> 'id', '')::uuid)`;

/** One field of the actor `transition()` passed, as text SQL. */
function actorText(field: string): string {
  return `nullif(nullif(current_setting('${ACTOR_SETTING}', true), '')::jsonb ->> ${sqlString(field)}, '')`;
}

/** One field of the actor `transition()` passed, as SQL of its column type. */
function actorField(field: string): string {
  return field === "ip" ? `${actorText(field)}::inet` : actorText(field);
}

/** The history columns and values a transition writes. */
function historyWrite(ctx: BlockSqlContext, item: Machine): string {
  const hist = item.history;
  const from = `old.${sqlIdent(item.column)}::text`;
  const to = `new.${sqlIdent(item.column)}::text`;

  if (hist === "app" || hist?.write === false) {
    return "";
  }

  if (hist !== undefined) {
    const table = quotedTable(hist.table);

    const columns: [string, string][] = [
      [hist.subject, `new.${sqlIdent(item.idColumn)}`],
      [hist.tenant, `new.${sqlIdent(item.tenantColumn)}`],
      [hist.from, asColumnType(table, hist.from, from)],
      [hist.to, asColumnType(table, hist.to, to)],
      [hist.actor, ACTOR_ID],
      [hist.reason, REASON],
      ...ACTOR_FIELDS.flatMap(([key, field]): [string, string][] => {
        const column = hist[key];

        return column === undefined
          ? []
          : [[column, asColumnType(table, column, actorText(field))]];
      }),
    ];

    return `insert into ${table} (${columns.map(([column]) => sqlIdent(column)).join(", ")})
        values (${columns.map(([, value]) => value).join(", ")});`;
  }

  const h = (column: string): string => ctx.col("history", column);

  const columns: [string, string][] = [
    [h("tenant"), `new.${sqlIdent(item.tenantColumn)}`],
    [h("subjectType"), sqlString(item.name)],
    [h("subjectId"), `new.${sqlIdent(item.idColumn)}::text`],
    [h("fromStatus"), ctx.cast("history", "fromStatus", from)],
    [h("toStatus"), ctx.cast("history", "toStatus", to)],
    [h("actor"), ACTOR_ID],
    [h("reason"), REASON],
    ...ACTOR_FIELDS.flatMap(([key, field]): [string, string][] =>
      ctx.has("history", key) ? [[h(key), actorField(field)]] : [],
    ),
  ];

  return `insert into ${ctx.table("history")} (${columns.map(([column]) => column).join(", ")})
        values (${columns.map(([, value]) => value).join(", ")});`;
}

/**
 * `<alias>.<id> = <value>`, on the id column's own type when the machine names
 * it.
 */
function idMatches(item: Machine, alias: string, value: string): string {
  const column = `${alias}.${sqlIdent(item.idColumn)}`;

  return item.idType === undefined
    ? `${column}::text = ${value}`
    : `${column} = (${value})::${item.idType}`;
}

const textArray = (items: readonly string[]): string =>
  `${sqlString(`{${items.join(",")}}`)}::text[]`;

function stageWrite(
  ctx: BlockSqlContext,
  item: Machine,
  kind: "open" | "advance",
): string {
  if (!item.stages || !ctx.hasTable("stages")) {
    return "";
  }

  const stages = ctx.table("stages");
  const tenant = ctx.col("stages", "tenant");
  const subjectType = ctx.col("stages", "subjectType");
  const subjectId = ctx.col("stages", "subjectId");
  const cleared = ctx.col("stages", "clearedAt");
  const display = ctx.col("stages", "display");
  const id = sqlIdent(item.idColumn);
  const newTenant = `new.${sqlIdent(item.tenantColumn)}`;

  const clear =
    kind === "advance"
      ? `update ${stages} set ${cleared} = now()
  where ${tenant} = ${newTenant}
    and ${subjectType} = ${sqlString(item.name)}
    and ${subjectId} = new.${id}::text
    and ${cleared} is null;`
      : "";

  return `${clear}
  insert into ${stages} (${tenant}, ${subjectType}, ${subjectId}, ${ctx.col("stages", "label")}, ${display})
  values (${newTenant}, ${sqlString(item.name)}, new.${id}::text, ${ctx.cast("stages", "label", `new.${sqlIdent(item.column)}::text`)},
    coalesce((select max(s.${display}) from ${stages} s
      where s.${tenant} = ${newTenant} and s.${subjectType} = ${sqlString(item.name)} and s.${subjectId} = new.${id}::text), 0) + 1);`;
}

function approvalGate(ctx: BlockSqlContext, item: Machine): string {
  const gated = Object.entries(item.requiresApproval).filter(
    ([, to]) => to.length > 0,
  );

  if (gated.length === 0) {
    return "";
  }

  const where = `blocks.state-machine.options.machines.${item.name}.requiresApproval`;

  if (!ctx.installed("approvals")) {
    throw new TypeError(`${where} needs the approvals module`);
  }

  const approvals = ctx.of("approvals");
  const a = (column: string): string => approvals.col("requests", column);

  const arms = gated
    .map(
      ([from, to]) =>
        `when ${sqlString(from)} then new.${sqlIdent(item.column)}::text = any (${textArray(to)})`,
    )
    .join(" ");

  return `
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old.${sqlIdent(item.column)}::text ${arms} else false end)
    and not ${SERVICE_CALLER}
    and not exists (
      select 1 from ${approvals.table("requests")} a
      where a.${a("id")}::text = nullif(current_setting('better_supabase.approval', true), '')
        and a.${a("status")} = 'approved'
        and a.${a("subjectType")} = ${sqlString(item.name)}
        and a.${a("subjectId")} = new.${sqlIdent(item.idColumn)}::text
    ) then
    ${fail("STATE_APPROVAL_REQUIRED", "that status change needs an approved request", "42501")}
  end if;`;
}

/** The trigger's event payload start: tenant, machine and record. */
function subjectPayload(item: Machine): string {
  return `'organizationId', new.${sqlIdent(item.tenantColumn)}::text, 'subjectType', ${sqlString(item.name)}, 'subjectId', new.${sqlIdent(item.idColumn)}::text`;
}

function lifecycleRecord(
  ctx: BlockSqlContext,
  item: Machine,
  type: "status.paused" | "status.resumed" | "status.flagged",
  extra: string,
): string {
  return ctx.record({
    type,
    payload: `jsonb_build_object(${subjectPayload(item)}${extra})`,
    tenant: `new.${sqlIdent(item.tenantColumn)}::text`,
    subject: `'statuses/${item.name}/' || new.${sqlIdent(item.idColumn)}::text`,
    audit: false,
  });
}

/**
 * The trigger branch that applies a lifecycle call: `pause_lifecycle`,
 * `resume_lifecycle` and `set_lifecycle_flag` update the status column to
 * itself as the caller, so the subject table's policies decide, and pass the
 * change in a transaction setting the trigger reads here.
 */
function lifecycleOps(ctx: BlockSqlContext, item: Machine): string {
  if (!item.lifecycle) {
    return "";
  }

  const life = ctx.table("lifecycles");
  const l = (column: string): string => ctx.col("lifecycles", column);
  const key = `${l("subjectType")} = ${sqlString(item.name)} and ${l("subjectId")} = new.${sqlIdent(item.idColumn)}::text`;
  const insertColumns = `${l("tenant")}, ${l("subjectType")}, ${l("subjectId")}, ${l("version")}`;
  const insertValues = `new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${sqlIdent(item.idColumn)}::text, ${String(item.version)}`;
  const changed = `perform set_config('${CHANGED_SETTING}', '1', true);`;

  return `
    v_op := nullif(current_setting('${OP_SETTING}', true), '')::jsonb;
    if v_op is not null and v_op ->> 'machine' = ${sqlString(item.name)} and v_op ->> 'id' = new.${sqlIdent(item.idColumn)}::text then
      case v_op ->> 'op'
        when 'pause' then
          if (v_op ->> 'until') is not null and (v_op ->> 'until')::timestamptz <= now() then
            ${fail("STATE_PAUSE_INVALID", "a pause must end in the future", "22023")}
          end if;
          insert into ${life} (${insertColumns}, ${l("pausedAt")}, ${l("pausedUntil")}, ${l("pauseReason")}, ${l("pausedBy")})
          values (${insertValues}, now(), (v_op ->> 'until')::timestamptz, nullif(v_op ->> 'reason', ''), auth.uid())
          on conflict (${l("subjectType")}, ${l("subjectId")}) do update set
            ${l("pausedAt")} = excluded.${l("pausedAt")},
            ${l("pausedUntil")} = excluded.${l("pausedUntil")},
            ${l("pauseReason")} = excluded.${l("pauseReason")},
            ${l("pausedBy")} = excluded.${l("pausedBy")},
            ${l("updatedAt")} = now();
          ${changed}
          ${lifecycleRecord(ctx, item, "status.paused", `, 'until', v_op ->> 'until', 'reason', nullif(v_op ->> 'reason', '')`)}
        when 'resume' then
          update ${life} set ${l("pausedAt")} = null, ${l("pausedUntil")} = null, ${l("pauseReason")} = null, ${l("pausedBy")} = null, ${l("updatedAt")} = now()
          where ${key} and ${l("pausedAt")} is not null;
          if found then
            ${changed}
            ${lifecycleRecord(ctx, item, "status.resumed", "")}
          end if;
        when 'flag' then
          v_flag := v_op ->> 'flag';
          if v_flag is null or not (v_flag = any (${textArray(item.flags)})) then
            ${fail("STATE_FLAG_UNKNOWN", "the machine has no such flag", "22023")}
          end if;
          select coalesce(${l("flags")}, '{}') into v_flags from ${life} where ${key} for update;
          v_flags := coalesce(v_flags, '{}');
          if coalesce((v_op ->> 'enabled')::boolean, false) is distinct from (v_flag = any (v_flags)) then
            v_flags := case when coalesce((v_op ->> 'enabled')::boolean, false)
              then v_flags || v_flag else array_remove(v_flags, v_flag) end;
            insert into ${life} (${insertColumns}, ${l("flags")})
            values (${insertValues}, v_flags)
            on conflict (${l("subjectType")}, ${l("subjectId")}) do update set
              ${l("flags")} = excluded.${l("flags")},
              ${l("updatedAt")} = now();
            ${changed}
            ${lifecycleRecord(ctx, item, "status.flagged", `, 'flag', v_flag, 'enabled', coalesce((v_op ->> 'enabled')::boolean, false)`)}
          end if;
        else
          ${fail("STATE_LIFECYCLE_INVALID", "unknown lifecycle change", "22023")}
      end case;
    end if;`;
}

/** The trigger check that refuses a transition while the record is paused. */
function pauseGate(ctx: BlockSqlContext, item: Machine): string {
  if (!item.lifecycle) {
    return "";
  }

  const life = ctx.table("lifecycles");
  const l = (column: string): string => ctx.col("lifecycles", column);
  const key = `${l("subjectType")} = ${sqlString(item.name)} and ${l("subjectId")} = new.${sqlIdent(item.idColumn)}::text`;

  return `
  select ${l("pausedUntil")}, ${l("pausedAt")} is not null into v_until, v_paused from ${life} where ${key};
  if coalesce(v_paused, false) then
    if v_until is null or v_until > now() then
      ${fail("STATE_PAUSED", "the record is paused; resume it first", "55000")}
    end if;
    update ${life} set ${l("pausedAt")} = null, ${l("pausedUntil")} = null, ${l("pauseReason")} = null, ${l("pausedBy")} = null, ${l("updatedAt")} = now()
    where ${key};
    ${lifecycleRecord(ctx, item, "status.resumed", "")}
  end if;`;
}

function lifecycleInsert(ctx: BlockSqlContext, item: Machine): string {
  if (!item.lifecycle) {
    return "";
  }

  const l = (column: string): string => ctx.col("lifecycles", column);

  return `insert into ${ctx.table("lifecycles")} (${l("tenant")}, ${l("subjectType")}, ${l("subjectId")}, ${l("version")})
    values (new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${sqlIdent(item.idColumn)}::text, ${String(item.version)})
    on conflict (${l("subjectType")}, ${l("subjectId")}) do nothing;`;
}

function trigger(ctx: BlockSqlContext, item: Machine): string {
  const allowed = Object.entries(item.transitions)
    .map(
      ([from, to]) =>
        `when ${sqlString(from)} then new.${sqlIdent(item.column)}::text = any (${textArray(to)})`,
    )
    .join(" ");

  const target = quotedTable(item.table);
  const tenant = `new.${sqlIdent(item.tenantColumn)}::text`;
  const subjectId = `new.${sqlIdent(item.idColumn)}::text`;
  const write = historyWrite(ctx, item);

  const declare = item.lifecycle
    ? `declare
  v_op jsonb;
  v_flag text;
  v_flags text[];
  v_until timestamptz;
  v_paused boolean;
${item.workflow === undefined ? "" : WORKFLOW_DECLARE}`
    : "";

  const insert =
    item.workflow === undefined
      ? `${
          item.optional
            ? ""
            : `if new.${sqlIdent(item.column)} is null then
      new.${sqlIdent(item.column)} := ${sqlString(item.initial)};
    end if;`
        }
    ${stageWrite(ctx, item, "open")}
    ${lifecycleInsert(ctx, item)}`
      : workflowInsert(ctx, item, stageWrite(ctx, item, "open"));

  const check =
    item.workflow === undefined
      ? `if ${item.optional ? `new.${sqlIdent(item.column)} is null or not (old.${sqlIdent(item.column)} is null and new.${sqlIdent(item.column)}::text = ${sqlString(item.initial)}) and ` : ""}not (case old.${sqlIdent(item.column)}::text ${allowed} else false end) then
    ${fail("STATE_TRANSITION_INVALID", "that status change is not allowed", "22023")}
  end if;`
      : workflowCheck(ctx, item);

  return `
create or replace function better_supabase.bsb_transition_${item.name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
${declare}begin
  if tg_op = 'INSERT' then
    ${insert}
    return new;
  end if;
  if new.${sqlIdent(item.column)} is not distinct from old.${sqlIdent(item.column)} then${lifecycleOps(ctx, item)}
    return new;
  end if;
  ${check}${approvalGate(ctx, item)}${pauseGate(ctx, item)}
  ${write}
  ${stageWrite(ctx, item, "advance")}
  ${ctx.record({
    type: "status.changed",
    payload: `jsonb_build_object('organizationId', ${tenant}, 'subjectType', ${sqlString(item.name)}, 'subjectId', ${subjectId}, 'from', old.${sqlIdent(item.column)}::text, 'to', new.${sqlIdent(item.column)}::text, 'reason', ${REASON})`,
    tenant,
    subject: `'statuses/${item.name}/' || ${subjectId}`,
    audit: false,
  })}
  return new;
end;
$$;
drop trigger if exists bsb_transition_${item.name} on ${target};
create trigger bsb_transition_${item.name} before insert or update of ${sqlIdent(item.column)} on ${target}
for each row execute function better_supabase.bsb_transition_${item.name}();`;
}

/** A `case subject_type` over the machines, with `unknown` for any other name. */
function byMachine(
  list: readonly Machine[],
  subjectType: string,
  branch: (item: Machine) => string,
): string {
  const unknown = fail("STATE_MACHINE_UNKNOWN", "unknown subject", "22023");

  if (list.length === 0) {
    return unknown;
  }

  return `case ${subjectType}
${list.map((item) => `    when ${sqlString(item.name)} then\n${branch(item)}`).join("\n")}
    else
      ${unknown}
  end case;`;
}

const NOT_FOUND = fail(
  "STATE_SUBJECT_NOT_FOUND",
  "no such record, or the caller can't see it",
  "P0002",
);

/**
 * The read policy of a module table: the caller sees a row when they can see
 * the record it belongs to, through the record table's own policies.
 */
function readPolicy(
  table: string,
  name: string,
  subjectType: string,
  subjectId: string,
  list: readonly Machine[],
): string {
  const visible =
    list.length === 0
      ? "false"
      : `case ${table}.${subjectType}
${list.map((item) => `      when ${sqlString(item.name)} then exists (select 1 from ${quotedTable(item.table)} s where ${idMatches(item, "s", `${table}.${subjectId}`)})`).join("\n")}
      else false
    end`;

  return renderPolicy(
    makePolicy({
      table,
      name,
      command: "select",
      roles: ["authenticated"],
      using: visible,
    }),
    { drop: true, target: table },
  );
}

const ACTOR_TYPES: Readonly<Record<(typeof ACTOR_FIELDS)[number][0], string>> =
  { actorName: "text", actorEmail: "text", ip: "inet", userAgent: "text" };

/** The history table's actor detail columns the app keeps. */
function actorColumns(ctx: BlockSqlContext): string {
  return ACTOR_FIELDS.filter(([key]) => ctx.has("history", key))
    .map(([key]) => `\n  ${ctx.col("history", key)} ${ACTOR_TYPES[key]},`)
    .join("");
}

function tables(ctx: BlockSqlContext, list: readonly Machine[]): string {
  if (!ctx.manages) {
    return "";
  }

  const history = ctx.table("history");
  const h = (column: string): string => ctx.col("history", column);

  const stages = ctx.hasTable("stages")
    ? `create table if not exists ${ctx.table("stages")} (
  ${ctx.col("stages", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("stages", "tenant")} ${ctx.idType} not null,
  ${ctx.col("stages", "subjectType")} text not null,
  ${ctx.col("stages", "subjectId")} text not null,
  ${ctx.col("stages", "label")} text not null,
  ${ctx.col("stages", "outcome")} text,
  ${ctx.col("stages", "display")} integer not null,
  ${ctx.col("stages", "clearedAt")} timestamptz,
  ${ctx.col("stages", "createdAt")} timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on ${ctx.table("stages")} (${ctx.col("stages", "subjectType")}, ${ctx.col("stages", "subjectId")});
${lockTable(ctx.table("stages"), { read: true })}
${readPolicy(ctx.table("stages"), "status_stages_read", ctx.col("stages", "subjectType"), ctx.col("stages", "subjectId"), list)}
`
    : "";

  const l = (column: string): string => ctx.col("lifecycles", column);

  const lifecycles = ctx.hasTable("lifecycles")
    ? `create table if not exists ${ctx.table("lifecycles")} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("subjectType")} text not null,
  ${l("subjectId")} text not null,
  ${l("version")} integer not null default 1,
  ${l("flags")} text[] not null default '{}',
  ${l("pausedAt")} timestamptz,
  ${l("pausedUntil")} timestamptz,
  ${l("pauseReason")} text,
  ${l("pausedBy")} uuid,
  ${l("createdAt")} timestamptz not null default now(),
  ${l("updatedAt")} timestamptz not null default now(),
  unique (${l("subjectType")}, ${l("subjectId")})
);
create index if not exists subject_lifecycles_paused_idx on ${ctx.table("lifecycles")} (${l("tenant")}, ${l("subjectType")}) where ${l("pausedAt")} is not null;
${lockTable(ctx.table("lifecycles"), { read: true })}
${readPolicy(ctx.table("lifecycles"), "subject_lifecycles_read", l("subjectType"), l("subjectId"), list)}
`
    : "";

  return `create table if not exists ${history} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("subjectType")} text not null,
  ${h("subjectId")} text not null,
  ${h("fromStatus")} text,
  ${h("toStatus")} text not null,
  ${h("actor")} uuid,${actorColumns(ctx)}
  ${h("reason")} text,
  ${h("createdAt")} timestamptz not null default now()
);
create index if not exists status_history_subject_idx on ${history} (${h("subjectType")}, ${h("subjectId")}, ${h("createdAt")} desc);
${lockTable(history, { read: true })}
${readPolicy(history, "status_history_read", h("subjectType"), h("subjectId"), list)}
${stages}${lifecycles}`;
}

/**
 * The body of `pause_lifecycle`, `resume_lifecycle` and `set_lifecycle_flag`:
 * pass `op` to the trigger and update the status column to itself as the
 * caller. Returns whether the trigger changed the lifecycle row.
 */
function lifecycleCall(
  list: readonly Machine[],
  fn: string,
  op: string,
): string {
  const disabled = fail(
    "STATE_LIFECYCLE_DISABLED",
    "the machine has no lifecycle; set lifecycle: true",
    "22023",
  );

  return `declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('${CHANGED_SETTING}', '', true);
  perform set_config('${OP_SETTING}', (${op})::text, true);
  ${byMachine(list, `${fn}.subject_type`, (item) =>
    item.lifecycle
      ? `      update ${quotedTable(item.table)} s set ${sqlIdent(item.column)} = s.${sqlIdent(item.column)}
      where ${idMatches(item, "s", `${fn}.subject_id`)};`
      : `      ${disabled}`,
  )}
  v_found := found;
  v_changed := current_setting('${CHANGED_SETTING}', true) = '1';
  perform set_config('${OP_SETTING}', '', true);
  perform set_config('${CHANGED_SETTING}', '', true);
  if not v_found then
    ${NOT_FOUND}
  end if;
  return v_changed;
end;`;
}

function readers(ctx: BlockSqlContext, list: readonly Machine[]): string {
  const visible = (item: Machine, fn: string): string =>
    `      if not exists (select 1 from ${quotedTable(item.table)} s where ${idMatches(item, "s", `${fn}.subject_id`)}) then
        ${NOT_FOUND}
      end if;`;

  const state = (item: Machine): string => {
    const steps = item.order.length;
    const graph = workflowState(ctx, item);

    const order =
      graph?.order ?? (steps === 0 ? "null::text[]" : textArray(item.order));

    const progress =
      graph?.progress ??
      (steps === 0
        ? "null"
        : `case when v_step is null then null when ${String(steps)} = 1 then 1 else round((v_step - 1)::numeric / ${String(steps - 1)}, 4) end`);

    const l = (column: string): string =>
      `v_life.${ctx.col("lifecycles", column)}`;

    const life = item.lifecycle
      ? `      select * into v_life from ${ctx.table("lifecycles")} x
      where x.${ctx.col("lifecycles", "subjectType")} = ${sqlString(item.name)} and x.${ctx.col("lifecycles", "subjectId")} = status_state.subject_id;
      v_paused := ${l("pausedAt")} is not null and (${l("pausedUntil")} is null or ${l("pausedUntil")} > now());`
      : "";

    const lifeJson = item.lifecycle
      ? `'version', ${l("version")}, 'flags', to_jsonb(coalesce(${l("flags")}, '{}')),
        'paused', v_paused, 'pausedAt', case when v_paused then ${l("pausedAt")} end,
        'pausedUntil', case when v_paused then ${l("pausedUntil")} end,
        'pauseReason', case when v_paused then ${l("pauseReason")} end${graph?.json ?? ""}`
      : `'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null`;

    return `      select s.${sqlIdent(item.column)}::text, s.${sqlIdent(item.tenantColumn)}::text into v_status, v_tenant
      from ${quotedTable(item.table)} s where ${idMatches(item, "s", "status_state.subject_id")};
      if not found then
        ${NOT_FOUND}
      end if;
${life}${graph?.load ?? ""}
      v_step := array_position(${order}, v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', ${sqlString(item.name)}, 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(${order}), 'step', v_step, 'steps', ${graph?.steps ?? (steps === 0 ? "null" : String(steps))}, 'progress', ${progress},
        ${lifeJson});`;
  };

  const limit = pageSize("list_status_history.max_rows", 50, 500);

  const history = (item: Machine): string => {
    const hist = item.history;

    if (hist === "app") {
      return `      ${fail("STATE_HISTORY_APP", "the app keeps this machine's history; read it from the app's own table", "0A000")}`;
    }

    const details = ACTOR_FIELDS.map(([key]) => {
      const column =
        hist === undefined
          ? ctx.has("history", key)
            ? `h.${ctx.col("history", key)}::text`
            : undefined
          : hist[key] === undefined
            ? undefined
            : `h.${sqlIdent(hist[key])}::text`;

      const value =
        key === "ip" && column !== undefined
          ? `regexp_replace(${column}, '/(32|128)$', '')`
          : column;

      return `${value ?? "null::text"} as ${sqlIdent(key)}`;
    }).join(", ");

    const rows = hist
      ? `select h.${sqlIdent(hist.id)}::text as id, h.${sqlIdent(hist.from)}::text as from_status, h.${sqlIdent(hist.to)}::text as to_status,
          h.${sqlIdent(hist.actor)}::text as actor, ${details}, h.${sqlIdent(hist.reason)}::text as reason, h.${sqlIdent(hist.createdAt)} as created_at
        from ${quotedTable(hist.table)} h
        where h.${sqlIdent(hist.subject)}::text = list_status_history.subject_id
          and (list_status_history.before is null or h.${sqlIdent(hist.createdAt)} < list_status_history.before)
        order by h.${sqlIdent(hist.createdAt)} desc
        limit ${limit}`
      : `select h.${ctx.col("history", "id")}::text as id, h.${ctx.col("history", "fromStatus")} as from_status, h.${ctx.col("history", "toStatus")} as to_status,
          h.${ctx.col("history", "actor")}::text as actor, ${details}, h.${ctx.col("history", "reason")} as reason, h.${ctx.col("history", "createdAt")} as created_at
        from ${ctx.table("history")} h
        where h.${ctx.col("history", "subjectType")} = ${sqlString(item.name)}
          and h.${ctx.col("history", "subjectId")} = list_status_history.subject_id
          and (list_status_history.before is null or h.${ctx.col("history", "createdAt")} < list_status_history.before)
        order by h.${ctx.col("history", "createdAt")} desc, h.${ctx.col("history", "id")} desc
        limit ${limit}`;

    return `${visible(item, "list_status_history")}${readLine(ctx.read("list_status_history.subject_type", "list_status_history.subject_id", "list_status_history"), "      ")}
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (${rows}) r
      ), '[]'::jsonb);`;
  };

  const st = (column: string): string => ctx.col("stages", column);

  const stages = (item: Machine): string =>
    item.stages
      ? `${visible(item, "list_status_stages")}
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', g.${st("id")}, 'label', g.${st("label")}, 'outcome', g.${st("outcome")},
          'display', g.${st("display")}, 'clearedAt', g.${st("clearedAt")}, 'createdAt', g.${st("createdAt")}) order by g.${st("display")})
        from ${ctx.table("stages")} g
        where g.${st("subjectType")} = ${sqlString(item.name)} and g.${st("subjectId")} = list_status_stages.subject_id
      ), '[]'::jsonb);`
      : `${visible(item, "list_status_stages")}
      return '[]'::jsonb;`;

  const lifeVar = list.some((item) => item.lifecycle)
    ? `\n  v_life ${ctx.table("lifecycles")}%rowtype;`
    : "";

  const orderVar = list.some((item) => item.workflow !== undefined)
    ? "\n  v_order text[];"
    : "";

  return `
-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function ${ctx.fn("status_state")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;${lifeVar}${orderVar}
begin
  ${byMachine(list, "status_state.subject_type", state)}
end;
$$;
${userGrant(`${ctx.fn("status_state")}(text, text)`)}

-- The record's status changes, newest first, as the caller.
create or replace function ${ctx.fn("list_status_history")}(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
${ctx.readVolatility()}
security invoker
set search_path = ''
as $$
begin
  ${byMachine(list, "list_status_history.subject_type", history)}
end;
$$;
${userGrant(`${ctx.fn("list_status_history")}(text, text, timestamptz, integer)`)}

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function ${ctx.fn("list_status_stages")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${byMachine(list, "list_status_stages.subject_type", stages)}
end;
$$;
${userGrant(`${ctx.fn("list_status_stages")}(text, text)`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const list = machines(ctx);

  for (const item of list) {
    if (item.stages && !ctx.hasTable("stages")) {
      throw new TypeError(
        `blocks.state-machine.options.machines.${item.name}.stages needs the stages table`,
      );
    }

    if (item.lifecycle && !ctx.hasTable("lifecycles")) {
      throw new TypeError(
        `blocks.state-machine.options.machines.${item.name}.lifecycle needs the lifecycles table`,
      );
    }
  }

  const transition = byMachine(
    list,
    "transition.subject_type",
    (item) =>
      `      update ${quotedTable(item.table)} s set ${sqlIdent(item.column)} = ${asColumnType(quotedTable(item.table), item.column, "transition.to_status")}
      where ${idMatches(item, "s", "transition.subject_id")};`,
  );

  return `${schemaPreamble(ctx)}
${tables(ctx, list)}${lifecycleWorkflowSql(ctx, list)}
${list.map((item) => trigger(ctx, item)).join("\n")}

drop function if exists ${ctx.fn("transition")}(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function ${ctx.fn("transition")}(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  ${transitionActorSql("transition.actor", "STATE_ACTOR_INVALID")}
  ${ctx.hook("before_status_transition", [
    ["text", "transition.subject_type"],
    ["text", "transition.subject_id"],
    ["text", "transition.to_status"],
  ])}
  ${transition}
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('${ACTOR_SETTING}', '', true);
  if not v_found then
    ${NOT_FOUND}
  end if;
  ${ctx.hook("after_status_transition", [
    ["text", "transition.subject_type"],
    ["text", "transition.to_status"],
  ])}
  return true;
end;
$$;
${userGrant(`${ctx.fn("transition")}(text, text, text, text, jsonb)`)}

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function ${ctx.fn("pause_lifecycle")}(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
${lifecycleCall(list, "pause_lifecycle", "jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason)")}
$$;
${userGrant(`${ctx.fn("pause_lifecycle")}(text, text, timestamptz, text)`)}

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function ${ctx.fn("resume_lifecycle")}(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
${lifecycleCall(list, "resume_lifecycle", "jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume')")}
$$;
${userGrant(`${ctx.fn("resume_lifecycle")}(text, text)`)}

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function ${ctx.fn("set_lifecycle_flag")}(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
${lifecycleCall(list, "set_lifecycle_flag", "jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false))")}
$$;
${userGrant(`${ctx.fn("set_lifecycle_flag")}(text, text, text, boolean)`)}
${readers(ctx, list)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "transition",
      args: ["text", "text", "text", "text", "jsonb"],
      returns: "boolean",
    },
    {
      name: "pause_lifecycle",
      args: ["text", "text", "timestamp with time zone", "text"],
      returns: "boolean",
    },
    { name: "resume_lifecycle", args: ["text", "text"], returns: "boolean" },
    {
      name: "set_lifecycle_flag",
      args: ["text", "text", "text", "boolean"],
      returns: "boolean",
    },
    { name: "status_state", args: ["text", "text"], returns: "jsonb" },
    {
      name: "list_status_history",
      args: ["text", "text", "timestamp with time zone", "integer"],
      returns: "jsonb",
    },
    { name: "list_status_stages", args: ["text", "text"], returns: "jsonb" },
  ];
}

function upgradeActorColumns(ctx: BlockSqlContext): string {
  const columns = ctx.owns("history")
    ? ACTOR_FIELDS.filter(([key]) => ctx.has("history", key)).map(
        ([key]) =>
          `alter table ${ctx.table("history")} add column if not exists ${ctx.col("history", key)} ${ACTOR_TYPES[key]};`,
      )
    : [];

  return [
    ...columns,
    `drop function if exists ${ctx.fn("transition")}(text, text, text, text);`,
  ].join("\n");
}

const CONTRIBUTES: BlockContributes = {
  bulk: (own) => [
    {
      name: "stateMachine.transition",
      run: `perform ${own.fn("transition")}(bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'to', bulk_row.args ->> 'reason', bulk_row.args -> 'actor');`,
    },
  ],
};

export const STATE_MACHINE: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "state-machine",
  scopes: ["tenant"],
  title: "State machine",
  description:
    "Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "approvals", "workflow-editor"],
  internal: [LIFECYCLE_INTERNAL],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "transition() runs as the caller, so the subject table's update policy applies, and raises STATE_SUBJECT_NOT_FOUND when no row changed; subject_lifecycles and the pause, resume, flag and reader functions are new.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        'status_history keeps the actor name, email, IP address and user agent that transition() takes as actor; history: "app" leaves the history to the app, and history.write: false only reads the app table.',
      sql: upgradeActorColumns,
    },
  ],
  names: NAMES,
  contract,
  build,
};
