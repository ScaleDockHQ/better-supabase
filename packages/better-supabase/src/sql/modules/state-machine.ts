import type { StateMachineEvents } from "../../blocks/state-machine/events.ts";
import type { SubjectsConfig } from "../../config/types/subjects.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  pageSize,
  quotedTable,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";

const SUBJECT = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: ModuleEvents<StateMachineEvents> = {
  "status.changed": {
    subject: "statuses",
    payload: [...SUBJECT, "from", "to"],
  },
  "status.paused": {
    subject: "statuses",
    payload: [...SUBJECT, "until", "reason"],
  },
  "status.resumed": {
    subject: "statuses",
    payload: [...SUBJECT],
  },
  "status.flagged": {
    subject: "statuses",
    payload: [...SUBJECT, "flag", "enabled"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_status_transition", "after_status_transition"],
  options: ["machines"],
  tables: {
    history: {
      name: "status_history",
      lifecycle: { tenant: "tenant", user: "actor", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        fromStatus: "from_status",
        toStatus: "to_status",
        actor: "actor_user_id",
        reason: "reason",
        createdAt: "created_at",
      },
    },
    stages: {
      name: "status_stages",
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
    },
    lifecycles: {
      name: "subject_lifecycles",
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
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const NAME = /^[a-z][a-z0-9_]*$/;
const ID_TYPE = /^[a-z][a-z0-9_ ]{0,62}$/;

/** The setting `pause_lifecycle`, `resume_lifecycle` and `set_lifecycle_flag` pass to the trigger. */
const OP_SETTING = "better_supabase.lifecycle_op";
/** Set by the trigger when a lifecycle call changed the row. */
const CHANGED_SETTING = "better_supabase.lifecycle_changed";

interface Machine {
  readonly name: string;
  readonly table: string;
  readonly column: string;
  readonly idColumn: string;
  /** The id column's type, so lookups compare on the primary key's own type. */
  readonly idType?: string;
  readonly tenantColumn: string;
  readonly initial: string;
  readonly transitions: Readonly<Record<string, readonly string[]>>;
  /** Transitions only an approved request of the approvals module may make. */
  readonly requiresApproval: Readonly<Record<string, readonly string[]>>;
  /** Writes a timeline row (label snapshot, display order, cleared_at). */
  readonly stages: boolean;
  /** Keeps a `subject_lifecycles` row: pause, flags and the pinned version. */
  readonly lifecycle: boolean;
  /** The machine version a new record is pinned to. */
  readonly version: number;
  /** The statuses in display order, for `step` and `progress`. */
  readonly order: readonly string[];
  /** The flags `set_lifecycle_flag` accepts. */
  readonly flags: readonly string[];
  readonly history?: {
    readonly table: string;
    readonly id: string;
    readonly from: string;
    readonly to: string;
    readonly actor: string;
    readonly reason: string;
    readonly subject: string;
    readonly tenant: string;
    readonly createdAt: string;
  };
}

function machines(ctx: ModuleContext): readonly Machine[] {
  const raw = ctx.option("machines");
  if (raw === undefined) return [];
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      "blocks.state-machine.options.machines must be an object",
    );
  }
  return Object.entries(raw).map(([name, entry]) =>
    machine(name, entry, ctx.subjects),
  );
}

/** The table keys of `config.subjects.<name>`, used when the machine names no table. */
function registered(
  name: string,
  registry: SubjectsConfig,
  where: string,
): Record<string, unknown> {
  const entry = Object.hasOwn(registry, name) ? registry[name] : undefined;
  if (entry === undefined) return {};
  if (entry.tenant === false) {
    throw new TypeError(
      `${where}: config.subjects.${name} has no tenant column, which a machine needs`,
    );
  }
  return {
    table: entry.table,
    ...(entry.id !== undefined && { id: entry.id }),
    ...(entry.idType !== undefined && { idType: entry.idType }),
    tenant: entry.tenant ?? "organization_id",
  };
}

function machine(
  name: string,
  entry: unknown,
  registry: SubjectsConfig,
): Machine {
  const where = `blocks.state-machine.options.machines.${name}`;
  if (!NAME.test(name)) throw new TypeError(`${where} has an invalid name`);
  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new TypeError(`${where} must be an object`);
  }
  const own: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(entry)) own[key] = value;
  const record =
    own["table"] === undefined
      ? { ...registered(name, registry, where), ...own }
      : own;
  const table = record["table"];
  const column = record["column"];
  const initial = record["initial"];
  const transitions = record["transitions"];
  if (typeof table !== "string" || typeof column !== "string") {
    throw new TypeError(`${where} needs table and column`);
  }
  if (!NAME.test(column)) {
    throw new TypeError(`${where}.column must be a column name`);
  }
  if (typeof initial !== "string") {
    throw new TypeError(`${where}.initial must be a status`);
  }
  if (
    typeof transitions !== "object" ||
    transitions === null ||
    Array.isArray(transitions)
  ) {
    throw new TypeError(
      `${where}.transitions must be an object of status to statuses`,
    );
  }
  const edges = edgesOf(transitions, `${where}.transitions`);
  const gated = edgesOf(
    record["requiresApproval"] ?? {},
    `${where}.requiresApproval`,
  );
  for (const [from, to] of Object.entries(gated)) {
    for (const status of to) {
      if (!edges[from]?.includes(status)) {
        throw new TypeError(
          `${where}.requiresApproval.${from}: ${status} is not an allowed transition`,
        );
      }
    }
  }
  const idType = record["idType"];
  if (
    idType !== undefined &&
    (typeof idType !== "string" || !ID_TYPE.test(idType))
  ) {
    throw new TypeError(`${where}.idType must be a type name such as uuid`);
  }
  const lifecycle = record["lifecycle"] ?? false;
  if (typeof lifecycle !== "boolean") {
    throw new TypeError(`${where}.lifecycle must be true or false`);
  }
  const version = record["version"] ?? 1;
  if (
    typeof version !== "number" ||
    !Number.isInteger(version) ||
    version < 1
  ) {
    throw new TypeError(`${where}.version must be a positive integer`);
  }
  const flags = namesOf(record["flags"], `${where}.flags`);
  if (!lifecycle && (record["version"] !== undefined || flags.length > 0)) {
    throw new TypeError(`${where}: version and flags need lifecycle: true`);
  }
  const statuses = new Set([
    initial,
    ...Object.keys(edges),
    ...Object.values(edges).flat(),
  ]);
  const order = statusList(record["order"], `${where}.order`);
  for (const status of order) {
    if (!statuses.has(status)) {
      throw new TypeError(`${where}.order: ${status} is not a status`);
    }
  }
  const history = historyOf(record["history"], where);
  return {
    name,
    table,
    column,
    idColumn: typeof record["id"] === "string" ? record["id"] : "id",
    ...(idType === undefined ? {} : { idType }),
    tenantColumn:
      typeof record["tenant"] === "string" ? record["tenant"] : "tenant_id",
    initial,
    transitions: edges,
    requiresApproval: gated,
    stages: record["stages"] === true,
    lifecycle,
    version,
    order,
    flags,
    ...(history === undefined ? {} : { history }),
  };
}

function edgesOf(
  value: unknown,
  where: string,
): Record<string, readonly string[]> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${where} must be an object of status to statuses`);
  }
  const edges: Record<string, readonly string[]> = {};
  for (const [from, to] of Object.entries(value)) {
    if (!Array.isArray(to) || to.some((item) => typeof item !== "string")) {
      throw new TypeError(`${where}.${from} must be a list of statuses`);
    }
    edges[from] = to;
  }
  return edges;
}

/** A list of distinct strings, or an empty list when unset. */
function statusList(value: unknown, where: string): readonly string[] {
  if (value === undefined) return [];
  if (
    !Array.isArray(value) ||
    value.some((item) => typeof item !== "string") ||
    new Set(value).size !== value.length
  ) {
    throw new TypeError(`${where} must be a list of distinct statuses`);
  }
  return value.map(String);
}

function namesOf(value: unknown, where: string): readonly string[] {
  const list = statusList(value, where);
  for (const item of list) {
    if (!NAME.test(item)) {
      throw new TypeError(
        `${where}: ${item} must be lowercase letters, digits and underscores`,
      );
    }
  }
  return list;
}

function historyOf(
  value: unknown,
  where: string,
): Machine["history"] | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${where}.history must be an object`);
  }
  const record: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) record[key] = item;
  const text = (key: string, fallback: string): string => {
    const item = record[key];
    if (item === undefined) return fallback;
    if (typeof item !== "string" || !NAME.test(item)) {
      throw new TypeError(`${where}.history.${key} must be a column name`);
    }
    return item;
  };
  const table = record["table"];
  if (typeof table !== "string") {
    throw new TypeError(`${where}.history.table is required`);
  }
  return {
    table,
    id: text("id", "id"),
    from: text("from", "from_status"),
    to: text("to", "to_status"),
    actor: text("actor", "actor_user_id"),
    reason: text("reason", "reason"),
    subject: text("subject", "subject_id"),
    tenant: text("tenant", "tenant_id"),
    createdAt: text("createdAt", "created_at"),
  };
}

/** `<alias>.<id> = <value>`, on the id column's own type when the machine names it. */
function idMatches(item: Machine, alias: string, value: string): string {
  const column = `${alias}.${sqlIdent(item.idColumn)}`;
  return item.idType === undefined
    ? `${column}::text = ${value}`
    : `${column} = (${value})::${item.idType}`;
}

const textArray = (items: readonly string[]): string =>
  `${sqlString(`{${items.join(",")}}`)}::text[]`;

function stageWrite(
  ctx: ModuleContext,
  item: Machine,
  kind: "open" | "advance",
): string {
  if (!item.stages || !ctx.hasTable("stages")) return "";
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
  values (${newTenant}, ${sqlString(item.name)}, new.${id}::text, new.${sqlIdent(item.column)},
    coalesce((select max(s.${display}) from ${stages} s
      where s.${tenant} = ${newTenant} and s.${subjectType} = ${sqlString(item.name)} and s.${subjectId} = new.${id}::text), 0) + 1);`;
}

function approvalGate(ctx: ModuleContext, item: Machine): string {
  const gated = Object.entries(item.requiresApproval).filter(
    ([, to]) => to.length > 0,
  );
  if (gated.length === 0) return "";
  const where = `blocks.state-machine.options.machines.${item.name}.requiresApproval`;
  if (!ctx.installed("approvals")) {
    throw new TypeError(`${where} needs the approvals module`);
  }
  const approvals = ctx.of("approvals");
  const a = (column: string): string => approvals.col("requests", column);
  const arms = gated
    .map(
      ([from, to]) =>
        `when ${sqlString(from)} then new.${sqlIdent(item.column)} = any (${textArray(to)})`,
    )
    .join(" ");
  return `
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old.${sqlIdent(item.column)} ${arms} else false end)
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
  ctx: ModuleContext,
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
 * itself as the caller, so the subject table's policies decide, and pass
 * the change in a transaction setting the trigger reads here.
 */
function lifecycleOps(ctx: ModuleContext, item: Machine): string {
  if (!item.lifecycle) return "";
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
function pauseGate(ctx: ModuleContext, item: Machine): string {
  if (!item.lifecycle) return "";
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

function lifecycleInsert(ctx: ModuleContext, item: Machine): string {
  if (!item.lifecycle) return "";
  const l = (column: string): string => ctx.col("lifecycles", column);
  return `insert into ${ctx.table("lifecycles")} (${l("tenant")}, ${l("subjectType")}, ${l("subjectId")}, ${l("version")})
    values (new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${sqlIdent(item.idColumn)}::text, ${String(item.version)})
    on conflict (${l("subjectType")}, ${l("subjectId")}) do nothing;`;
}

function trigger(ctx: ModuleContext, item: Machine): string {
  const history = ctx.table("history");
  const allowed = Object.entries(item.transitions)
    .map(
      ([from, to]) =>
        `when ${sqlString(from)} then new.${sqlIdent(item.column)} = any (${textArray(to)})`,
    )
    .join(" ");
  const target = quotedTable(item.table);
  const tenant = `new.${sqlIdent(item.tenantColumn)}::text`;
  const subjectId = `new.${sqlIdent(item.idColumn)}::text`;
  const hist = item.history;
  const write = hist
    ? `insert into ${quotedTable(hist.table)} (${sqlIdent(hist.subject)}, ${sqlIdent(hist.tenant)}, ${sqlIdent(hist.from)}, ${sqlIdent(hist.to)}, ${sqlIdent(hist.actor)}, ${sqlIdent(hist.reason)})
        values (new.${sqlIdent(item.idColumn)}, new.${sqlIdent(item.tenantColumn)}, old.${sqlIdent(item.column)}, new.${sqlIdent(item.column)}, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));`
    : `insert into ${history} (${ctx.col("history", "tenant")}, ${ctx.col("history", "subjectType")}, ${ctx.col("history", "subjectId")}, ${ctx.col("history", "fromStatus")}, ${ctx.col("history", "toStatus")}, ${ctx.col("history", "actor")}, ${ctx.col("history", "reason")})
        values (new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${sqlIdent(item.idColumn)}::text, old.${sqlIdent(item.column)}, new.${sqlIdent(item.column)}, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));`;
  const declare = item.lifecycle
    ? `declare
  v_op jsonb;
  v_flag text;
  v_flags text[];
  v_until timestamptz;
  v_paused boolean;
`
    : "";
  return `
create or replace function better_supabase.bs_transition_${item.name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
${declare}begin
  if tg_op = 'INSERT' then
    if new.${sqlIdent(item.column)} is null then
      new.${sqlIdent(item.column)} := ${sqlString(item.initial)};
    end if;
    ${stageWrite(ctx, item, "open")}
    ${lifecycleInsert(ctx, item)}
    return new;
  end if;
  if new.${sqlIdent(item.column)} is not distinct from old.${sqlIdent(item.column)} then${lifecycleOps(ctx, item)}
    return new;
  end if;
  if not (case old.${sqlIdent(item.column)} ${allowed} else false end) then
    ${fail("STATE_TRANSITION_INVALID", "that status change is not allowed", "22023")}
  end if;${approvalGate(ctx, item)}${pauseGate(ctx, item)}
  ${write}
  ${stageWrite(ctx, item, "advance")}
  ${ctx.record({
    type: "status.changed",
    payload: `jsonb_build_object('organizationId', ${tenant}, 'subjectType', ${sqlString(item.name)}, 'subjectId', ${subjectId}, 'from', old.${sqlIdent(item.column)}::text, 'to', new.${sqlIdent(item.column)}::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), ''))`,
    tenant,
    subject: `'statuses/${item.name}/' || ${subjectId}`,
    audit: false,
  })}
  return new;
end;
$$;
drop trigger if exists bs_transition_${item.name} on ${target};
create trigger bs_transition_${item.name} before insert or update of ${sqlIdent(item.column)} on ${target}
for each row execute function better_supabase.bs_transition_${item.name}();`;
}

/** A `case subject_type` over the machines, with `unknown` for any other name. */
function byMachine(
  list: readonly Machine[],
  subjectType: string,
  branch: (item: Machine) => string,
): string {
  const unknown = fail("STATE_MACHINE_UNKNOWN", "unknown subject", "22023");
  if (list.length === 0) return unknown;
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
 * The read policy of a module table: the caller sees a row when they can
 * see the record it belongs to, through the record table's own policies.
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
  return `drop policy if exists ${name} on ${table};
create policy ${name} on ${table} for select to authenticated
  using (${visible});`;
}

function tables(ctx: ModuleContext, list: readonly Machine[]): string {
  if (!ctx.manages) return "";
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
  ${h("actor")} uuid,
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

function readers(ctx: ModuleContext, list: readonly Machine[]): string {
  const visible = (item: Machine, fn: string): string =>
    `      if not exists (select 1 from ${quotedTable(item.table)} s where ${idMatches(item, "s", `${fn}.subject_id`)}) then
        ${NOT_FOUND}
      end if;`;
  const state = (item: Machine): string => {
    const steps = item.order.length;
    const order = steps === 0 ? "null::text[]" : textArray(item.order);
    const progress =
      steps === 0
        ? "null"
        : `case when v_step is null then null when ${String(steps)} = 1 then 1 else round((v_step - 1)::numeric / ${String(steps - 1)}, 4) end`;
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
        'pauseReason', case when v_paused then ${l("pauseReason")} end`
      : `'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null`;
    return `      select s.${sqlIdent(item.column)}::text, s.${sqlIdent(item.tenantColumn)}::text into v_status, v_tenant
      from ${quotedTable(item.table)} s where ${idMatches(item, "s", "status_state.subject_id")};
      if not found then
        ${NOT_FOUND}
      end if;
${life}
      v_step := array_position(${order}, v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', ${sqlString(item.name)}, 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(${order}), 'step', v_step, 'steps', ${steps === 0 ? "null" : String(steps)}, 'progress', ${progress},
        ${lifeJson});`;
  };
  const limit = pageSize("list_status_history.max_rows", 50, 500);
  const history = (item: Machine): string => {
    const hist = item.history;
    const rows = hist
      ? `select h.${sqlIdent(hist.id)}::text as id, h.${sqlIdent(hist.from)}::text as from_status, h.${sqlIdent(hist.to)}::text as to_status,
          h.${sqlIdent(hist.actor)}::text as actor, h.${sqlIdent(hist.reason)}::text as reason, h.${sqlIdent(hist.createdAt)} as created_at
        from ${quotedTable(hist.table)} h
        where h.${sqlIdent(hist.subject)}::text = list_status_history.subject_id
          and (list_status_history.before is null or h.${sqlIdent(hist.createdAt)} < list_status_history.before)
        order by h.${sqlIdent(hist.createdAt)} desc
        limit ${limit}`
      : `select h.${ctx.col("history", "id")}::text as id, h.${ctx.col("history", "fromStatus")} as from_status, h.${ctx.col("history", "toStatus")} as to_status,
          h.${ctx.col("history", "actor")}::text as actor, h.${ctx.col("history", "reason")} as reason, h.${ctx.col("history", "createdAt")} as created_at
        from ${ctx.table("history")} h
        where h.${ctx.col("history", "subjectType")} = ${sqlString(item.name)}
          and h.${ctx.col("history", "subjectId")} = list_status_history.subject_id
          and (list_status_history.before is null or h.${ctx.col("history", "createdAt")} < list_status_history.before)
        order by h.${ctx.col("history", "createdAt")} desc, h.${ctx.col("history", "id")} desc
        limit ${limit}`;
    return `${visible(item, "list_status_history")}
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
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
  v_paused boolean := false;${lifeVar}
begin
  ${byMachine(list, "status_state.subject_type", state)}
end;
$$;
${userGrant(`${ctx.fn("status_state")}(text, text)`)}

-- The record's status changes, newest first, as the caller.
create or replace function ${ctx.fn("list_status_history")}(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
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

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
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
      `      update ${quotedTable(item.table)} s set ${sqlIdent(item.column)} = transition.to_status
      where ${idMatches(item, "s", "transition.subject_id")};`,
  );
  return `${schemaPreamble(ctx)}
${tables(ctx, list)}
${list.map((item) => trigger(ctx, item)).join("\n")}

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge.
create or replace function ${ctx.fn("transition")}(subject_type text, subject_id text, to_status text, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  ${ctx.hook("before_status_transition", [
    ["text", "transition.subject_type"],
    ["text", "transition.subject_id"],
    ["text", "transition.to_status"],
  ])}
  ${transition}
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
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
${userGrant(`${ctx.fn("transition")}(text, text, text, text)`)}

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

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "transition",
      args: ["text", "text", "text", "text"],
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

export const STATE_MACHINE: ModuleDefinition = {
  name: "state-machine",
  scopes: ["tenant"],
  title: "State machine",
  description:
    "Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit", "approvals"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "transition() runs as the caller, so the subject table's update policy applies, and raises STATE_SUBJECT_NOT_FOUND when no row changed; subject_lifecycles and the pause, resume, flag and reader functions are new.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
