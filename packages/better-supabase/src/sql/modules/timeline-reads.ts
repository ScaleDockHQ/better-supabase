import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { pageSize, SERVICE_CALLER } from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { hasColumn } from "./audit-columns.ts";
import { moduleOperations, OPERATIONS } from "./permissions-model.ts";
import { machines } from "./state-machine-options.ts";

export interface ActivityReads {
  /** The activity_subject_readable function, before the read policy. */
  readonly readable: string;
  /** Drops activity_subject_readable when the policy doesn't call it. */
  readonly dropReadable: string;
  /** The per-row registry check appended to the read policy. */
  readonly rowCheck: string;
  /** List_activity's early return for a subject the caller can't read. */
  readonly gate: string;
  /** Sets v_table to the subject type's registry table. */
  readonly auditSetup: string;
  /** The audit log entries on the subject's row, unioned into the timeline. */
  readonly auditBranch: string;
  /**
   * The subject's workflow runs, notification deliveries, status transitions
   * and messages, unioned into the timeline.
   */
  readonly sourceBranches: string;
  /**
   * `and not (...)` for the event branch: drops the stored entries a read-time
   * branch returns for this call, so a status change or message shows once.
   */
  readonly eventDedupe: string;
  /** Activity_subject_deliveries, or the statement that drops it. */
  readonly helpers: string;
  /** The sources list_activity can return, in order. */
  readonly sources: readonly ActivitySourceName[];
}

export type ActivitySourceName =
  | "event"
  | "audit"
  | "delivery"
  | "run"
  | "transition"
  | "message";

/**
 * A read-time branch of list_activity, and the condition under which it returns
 * rows for the call (empty when the branch is off).
 */
interface ReadBranch {
  readonly sql: string;
  readonly covers: string;
}

const NO_BRANCH: ReadBranch = { sql: "", covers: "" };

const DELIVERIES_SIGNATURE = (ctx: BlockSqlContext): string =>
  `${ctx.fn("activity_subject_deliveries")}(${ctx.idType}, text, text, timestamptz, integer)`;

/**
 * How the activity feed reads through the `subjects` registry and the audit
 * log. A registered subject type needs `can_subject(read)`, per row in the read
 * policy and once for a subject's timeline; types the registry doesn't know
 * keep the tenant check alone. With `audit` and its `readPolicy`, a registered
 * subject's timeline also returns the log's entries on its row, which that
 * policy gates by the audit read permission.
 */
export function activityReads(ctx: BlockSqlContext): ActivityReads {
  const none: ActivityReads = {
    readable: "",
    dropReadable: `\ndrop function if exists ${ctx.fn("activity_subject_readable")}(text, text);`,
    rowCheck: "",
    gate: "",
    auditSetup: "",
    auditBranch: "",
    sourceBranches: "",
    eventDedupe: "",
    helpers: `\ndrop function if exists ${DELIVERIES_SIGNATURE(ctx)};`,
    sources: ["event"],
  };

  if (!ctx.installed("subjects")) {
    return none;
  }

  const registry = registeredSubjects(ctx.subjects, ctx.naming);

  if (registry.length === 0) {
    return none;
  }

  const a = (logical: string): string => ctx.col("activity", logical);
  const readable = ctx.fn("activity_subject_readable");
  const types = `${sqlString(`{${registry.map((subject) => subject.type).join(",")}}`)}::text[]`;
  const audit = ctx.installed("audit") ? ctx.of("audit") : undefined;

  const auditOn =
    audit !== undefined &&
    audit.mode !== "custom" &&
    audit.flag("readPolicy", false) &&
    hasColumn(audit, "log", "table") &&
    hasColumn(audit, "log", "record");

  const runs = runBranch(ctx, types);
  const transitions = transitionBranch(ctx, types);
  const messages = messageBranch(ctx, types);
  const type = `y.${ctx.col("activity", "type")}`;

  const covered = [
    ...(transitions.covers === ""
      ? []
      : [`(${type} = 'status.changed' and ${transitions.covers})`]),
    ...(messages.covers === ""
      ? []
      : [
          `(${type} in ('message.sent', 'comment.posted') and ${messages.covers})`,
        ]),
  ];

  const deliveries = deliveryHelper(ctx, types);

  return {
    // PL/pgSQL resolves can_subject when it runs: the subjects module
    // installs after this one.
    readable: `-- Whether the caller can read a registered subject (can_subject).
create or replace function ${readable}(subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return coalesce(${ctx.of("subjects").fn("can_subject")}(subject_type, subject_id, 'read'), false);
end;
$$;
revoke execute on function ${readable}(text, text) from public, anon;
grant execute on function ${readable}(text, text) to authenticated, service_role;
`,
    dropReadable: "",
    rowCheck: `
    and (${a("subjectType")} is null or ${a("subjectId")} is null
      or not (${a("subjectType")} = any (${types}))
      or ${readable}(${a("subjectType")}, ${a("subjectId")}))`,
    gate: `
  if list_activity.subject_id is not null and list_activity.subject_type = any (${types})
    and not ${readable}(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;`,
    auditSetup: auditOn
      ? `
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
${registry.map((subject) => `      when ${sqlString(subject.type)} then ${sqlString(`${subject.schema}.${subject.table}`)}`).join("\n")}
    end;
  end if;`
      : "",
    auditBranch: auditOn ? auditBranch(ctx, audit) : "",
    sourceBranches: `${runs}${transitions.sql}${messages.sql}${
      deliveries === undefined
        ? ""
        : `
    union all
    (select d.entry, d.at, d.id
    from ${ctx.fn("activity_subject_deliveries")}(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))`
    }`,
    eventDedupe:
      covered.length === 0
        ? ""
        : `
      and not (${covered.join("\n        or ")})`,
    helpers:
      deliveries ?? `\ndrop function if exists ${DELIVERIES_SIGNATURE(ctx)};`,
    sources: [
      "event",
      ...(auditOn ? (["audit"] as const) : []),
      ...(deliveries === undefined ? [] : (["delivery"] as const)),
      ...(runs === "" ? [] : (["run"] as const)),
      ...(transitions.sql === "" ? [] : (["transition"] as const)),
      ...(messages.sql === "" ? [] : (["message"] as const)),
    ],
  };
}

/**
 * An activity entry's keys, with the activity table's column names. A column
 * the app maps to null has no key, as in the feed's own rows.
 */
function entry(
  ctx: BlockSqlContext,
  values: Readonly<Record<string, string>>,
  source: ActivitySourceName,
): string {
  const key = (logical: string): string =>
    sqlString(ctx.col("activity", logical).replaceAll('"', ""));

  return [
    ...Object.entries(values)
      .filter(([logical]) => ctx.has("activity", logical))
      .map(([logical, value]) => `${key(logical)}, ${value}`),
    `'source', ${sqlString(source)}`,
  ].join(", ");
}

/**
 * The subject's workflow runs. list_activity runs as the caller, so the runs'
 * own read policy applies on top of the can_subject gate.
 */
function runBranch(ctx: BlockSqlContext, types: string): string {
  if (ctx.scope.kind !== "tenant" || !ctx.installed("workflows")) {
    return "";
  }

  const w = ctx.of("workflows");

  const ready =
    w.mode !== "custom" &&
    w.hasTable("runs") &&
    ["tenant", "subjectType", "subjectId", "status", "createdAt"].every(
      (logical) => w.has("runs", logical),
    );

  if (!ready) {
    return "";
  }

  const r = (logical: string): string => `r.${w.col("runs", logical)}`;

  const optional = (logical: string): string =>
    w.has("runs", logical) ? r(logical) : "null::text";

  const data = [
    `'runId', ${r("id")}`,
    `'definition', ${optional("definition")}`,
    `'engine', ${optional("engine")}`,
    `'status', ${r("status")}`,
    `'mode', ${optional("mode")}`,
    `'error', ${w.has("runs", "error") ? `${r("error")}::text` : "null::text"}`,
    `'completedAt', ${w.has("runs", "completedAt") ? r("completedAt") : "null::timestamptz"}`,
  ];

  const values = {
    id: `${r("id")}::text`,
    tenant: r("tenant"),
    event: "null::text",
    type: `'run.' || ${r("status")}`,
    actor: w.has("runs", "actor") ? r("actor") : "null::uuid",
    subjectType: "list_activity.subject_type",
    subjectId: "list_activity.subject_id",
    summary: "null::text",
    data: `jsonb_strip_nulls(jsonb_build_object(${data.join(", ")}))`,
    occurredAt: r("createdAt"),
  };

  return `
    union all
    (select jsonb_build_object(${entry(ctx, values, "run")}) as entry,
      ${r("createdAt")} as at, ${r("id")}::text as id
    from ${w.table("runs")} r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any (${types})
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and ${r("tenant")} = list_activity.tenant
      and ${r("subjectType")} = list_activity.subject_type
      and ${r("subjectId")} = list_activity.subject_id
      and (list_activity.before is null or ${r("createdAt")} < list_activity.before)
    order by ${r("createdAt")} desc, ${r("id")} desc
    limit v_limit)`;
}

/**
 * The subject's status changes from the state-machine's `status_history`, for
 * the machines that write it (a machine with its own `history` table is
 * skipped). As the caller, so the history's read policy applies.
 */
function transitionBranch(ctx: BlockSqlContext, types: string): ReadBranch {
  if (ctx.scope.kind !== "tenant" || !ctx.installed("state-machine")) {
    return NO_BRANCH;
  }

  const sm = ctx.of("state-machine");

  if (sm.mode === "custom") {
    return NO_BRANCH;
  }

  const names = machines(sm)
    .filter((item) => item.history === undefined)
    .map((item) => item.name);

  if (names.length === 0) {
    return NO_BRANCH;
  }

  const h = (logical: string): string => `h.${sm.col("history", logical)}`;

  const data = [
    `'from', ${h("fromStatus")}::text`,
    `'to', ${h("toStatus")}::text`,
    `'reason', ${h("reason")}`,
  ];

  const values = {
    id: `${h("id")}::text`,
    tenant: h("tenant"),
    event: "null::text",
    type: "'status.changed'",
    actor: h("actor"),
    subjectType: "list_activity.subject_type",
    subjectId: "list_activity.subject_id",
    summary: "null::text",
    data: `jsonb_strip_nulls(jsonb_build_object(${data.join(", ")}))`,
    occurredAt: h("createdAt"),
  };

  const covers = `list_activity.subject_id is not null
      and list_activity.subject_type = any (${types})
      and list_activity.subject_type = any (${sqlString(`{${names.join(",")}}`)}::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources))`;

  const sql = `
    union all
    (select jsonb_build_object(${entry(ctx, values, "transition")}) as entry,
      ${h("createdAt")} as at, ${h("id")}::text as id
    from ${sm.table("history")} h
    where ${covers}
      and ${h("tenant")} = list_activity.tenant
      and ${h("subjectType")} = list_activity.subject_type
      and ${h("subjectId")} = list_activity.subject_id
      and (list_activity.before is null or ${h("createdAt")} < list_activity.before)
    order by ${h("createdAt")} desc, ${h("id")} desc
    limit v_limit)`;

  return { sql, covers };
}

/**
 * The sent messages of the subject's conversation in messaging. As the caller,
 * so the conversation's access decides which the caller sees.
 */
function messageBranch(ctx: BlockSqlContext, types: string): ReadBranch {
  if (ctx.scope.kind !== "tenant" || !ctx.installed("messaging")) {
    return NO_BRANCH;
  }

  const ms = ctx.of("messaging");

  const ready =
    ms.mode !== "custom" &&
    ms.has("conversations", "subjectType") &&
    ms.has("conversations", "subjectId");

  if (!ready) {
    return NO_BRANCH;
  }

  const m = (logical: string): string => `m.${ms.col("messages", logical)}`;

  const c = (logical: string): string =>
    `c.${ms.col("conversations", logical)}`;

  const data = [
    `'messageId', ${m("id")}`,
    `'conversationId', ${m("conversation")}`,
    `'threadId', ${m("thread")}`,
    `'kind', ${m("kind")}::text`,
  ];

  const values = {
    id: `${m("id")}::text`,
    tenant: m("tenant"),
    event: "null::text",
    type: `case when ${c("kind")} = 'subject' then 'comment.posted' else 'message.sent' end`,
    actor: m("author"),
    subjectType: "list_activity.subject_type",
    subjectId: "list_activity.subject_id",
    summary: `left(${m("body")}, 280)`,
    data: `jsonb_strip_nulls(jsonb_build_object(${data.join(", ")}))`,
    occurredAt: m("sentAt"),
  };

  const covers = `list_activity.subject_id is not null
      and list_activity.subject_type = any (${types})
      and (list_activity.sources is null or 'message' = any (list_activity.sources))`;

  const sql = `
    union all
    (select jsonb_build_object(${entry(ctx, values, "message")}) as entry,
      ${m("sentAt")} as at, ${m("id")}::text as id
    from ${ms.table("messages")} m
    join ${ms.table("conversations")} c on ${c("id")} = ${m("conversation")}
    where ${covers}
      and ${c("tenant")} = list_activity.tenant
      and ${c("subjectType")} = list_activity.subject_type
      and ${c("subjectId")} = list_activity.subject_id
      and ${m("sentAt")} is not null
      and ${m("deletedAt")} is null
      and (list_activity.before is null or ${m("sentAt")} < list_activity.before)
    order by ${m("sentAt")} desc, ${m("id")} desc
    limit v_limit)`;

  return { sql, covers };
}

/**
 * Activity_subject_deliveries: the deliveries of the notifications about a
 * registered subject. Deliveries are readable only by their recipient, so it
 * runs as definer and asks for the activity read and notification send
 * permissions in the tenant, the bar list_subject_deliveries sets.
 * list_activity has already checked can_subject.
 */
function deliveryHelper(
  ctx: BlockSqlContext,
  types: string,
): string | undefined {
  if (ctx.scope.kind !== "tenant" || !ctx.installed("notifications")) {
    return undefined;
  }

  const n = ctx.of("notifications");

  const has = (table: string, logical: string): boolean =>
    n.hasTable(table) && n.has(table, logical);

  const ready =
    n.mode !== "custom" &&
    n.hasTable("deliveries") &&
    has("events", "subjectType") &&
    has("events", "subjectId") &&
    has("events", "tenant");

  if (!ready) {
    return undefined;
  }

  const fn = "activity_subject_deliveries";
  const d = (logical: string): string => `d.${n.col("deliveries", logical)}`;
  const rc = (logical: string): string => `rc.${n.col("recipients", logical)}`;
  const ev = (logical: string): string => `ev.${n.col("events", logical)}`;

  const data = [
    `'notificationId', ${ev("id")}`,
    `'notificationType', ${ev("type")}`,
    `'channel', ${d("channel")}`,
    `'status', ${d("status")}`,
    `'userId', ${rc("user")}`,
    ...(
      [
        ["providerStatus", "providerStatus"],
        ["templateKey", "templateKey"],
        ["error", "error"],
        ["deliveredAt", "deliveredAt"],
      ] as const
    ).flatMap(([key, logical]) =>
      has("deliveries", logical) ? [`'${key}', ${d(logical)}`] : [],
    ),
  ];

  const values = {
    id: `${d("id")}::text`,
    tenant: ev("tenant"),
    event: "null::text",
    type: `'delivery.' || ${d("status")}`,
    actor: "null::uuid",
    subjectType: `${fn}.subject_type`,
    subjectId: `${fn}.subject_id`,
    summary: has("events", "summary") ? ev("summary") : "null::text",
    data: `jsonb_strip_nulls(jsonb_build_object(${data.join(", ")}))`,
    occurredAt: d("createdAt"),
  };

  const activity = ctx.permission("read", moduleOperations("timeline").read);

  const send = ctx.permission("send", OPERATIONS["notifications.send"]);
  const signature = DELIVERIES_SIGNATURE(ctx);

  return `
-- The deliveries of the notifications about a registered subject, for
-- list_activity. Deliveries are readable only by their recipient, so this
-- runs as definer and needs activity read and notification send in tenant.
create or replace function ${ctx.fn(fn)}(tenant ${ctx.idType}, subject_type text, subject_id text, before timestamptz, max_rows integer)
returns table (entry jsonb, at timestamptz, id text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select jsonb_build_object(${entry(ctx, values, "delivery")}),
    ${d("createdAt")}, ${d("id")}::text
  from ${n.table("deliveries")} d
  join ${n.table("recipients")} rc on ${rc("id")} = ${d("recipient")}
  join ${n.table("events")} ev on ${ev("id")} = ${rc("event")}
  where ${fn}.subject_type = any (${types})
    and ((${SERVICE_CALLER})
      or (${ctx.scope.can(`${fn}.tenant`, activity)} and ${ctx.scope.can(`${fn}.tenant`, send)}))
    and ${ev("tenant")} = ${fn}.tenant
    and ${ev("subjectType")} = ${fn}.subject_type
    and ${ev("subjectId")} = ${fn}.subject_id
    and (${fn}.before is null or ${d("createdAt")} < ${fn}.before)
  order by ${d("createdAt")} desc, ${d("id")} desc
  limit ${pageSize(`${fn}.max_rows`, 50, 500)};
end;
$$;
revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;
`;
}

/** The union branch that reads the audit log's entries on v_table's row. */
function auditBranch(ctx: BlockSqlContext, audit: BlockSqlContext): string {
  const a = (logical: string): string =>
    sqlString(ctx.col("activity", logical).replaceAll('"', ""));

  // The pair, or nothing when the app maps the activity column to null.
  const pair = (logical: string, value: string): readonly string[] =>
    ctx.has("activity", logical) ? [`${a(logical)}, ${value}`] : [];

  const l = (logical: string): string => `l.${audit.col("log", logical)}`;
  const has = (logical: string): boolean => hasColumn(audit, "log", logical);
  const op = has("op") ? l("op") : "null::text";

  const type = has("eventType")
    ? `coalesce(${l("eventType")}, 'audit.' || ${op})`
    : `'audit.' || coalesce(${op}, 'event')`;

  const data = [
    `'op', ${op}`,
    ...(has("changed") ? [`'changed', to_jsonb(${l("changed")})`] : []),
    `'table', ${l("table")}`,
  ];

  const entry = [
    `${a("id")}, ${l("id")}::text`,
    `${a("tenant")}, ${l("tenant")}`,
    `${a("event")}, null::text`,
    `${a("type")}, ${type}`,
    ...pair("actor", l("actor")),
    `${a("subjectType")}, list_activity.subject_type`,
    `${a("subjectId")}, list_activity.subject_id`,
    ...pair("summary", has("summary") ? l("summary") : "null::text"),
    `${a("data")}, jsonb_strip_nulls(jsonb_build_object(${data.join(", ")}))`,
    `${a("occurredAt")}, ${l("occurredAt")}`,
    `'source', 'audit'`,
  ];

  return `
    union all
    (select jsonb_build_object(${entry.join(", ")}) as entry,
      ${l("occurredAt")} as at, ${l("id")}::text as id
    from ${audit.table("log")} l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and ${l("table")} = v_table
      and ${l("record")} = list_activity.subject_id
      and ${ctx.scope.eq(l("tenant"), ctx.scope.value("list_activity.tenant"))}
      and (list_activity.before is null or ${l("occurredAt")} < list_activity.before)
    order by ${l("occurredAt")} desc, ${l("id")} desc
    limit v_limit)`;
}
