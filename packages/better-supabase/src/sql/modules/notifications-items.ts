import type { ModuleContext } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

export function integerMutations(ctx: ModuleContext): string {
  return [
    `${ctx.fn("mark_notifications_unread")}(uuid[], ${ctx.idType})`,
    `${ctx.fn("mark_notifications_read")}(uuid[], ${ctx.idType})`,
    `${ctx.fn("dismiss_notifications")}(uuid[])`,
    `${ctx.fn("resolve_notifications")}(text, text, text, ${ctx.idType})`,
  ]
    .map((signature) => `drop function if exists ${signature};`)
    .join("\n");
}

export function changedJson(n: NotifyNames): string {
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);
  return `select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(${itemJson(n)} order by rc.${r("createdAt")} desc, rc.${r("id")} desc) filter (where rc.${r("user")} = auth.uid()), '[]')
  )
  from rc
  join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}`;
}

export function itemJson(n: NotifyNames): string {
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const pairs: [string, string][] = [
    ["id", `rc.${r("id")}`],
    ["event_id", `ev.${e("id")}`],
    ["type", `ev.${e("type")}`],
    ["data", `ev.${e("data")}`],
    ["created_at", `rc.${r("createdAt")}`],
    ["read_at", `rc.${r("readAt")}`],
  ];
  const optional: [string, string, string][] = [
    ["tenant", "events", "tenant"],
    ["actor_id", "events", "actor"],
    ["subject_type", "events", "subjectType"],
    ["subject_id", "events", "subjectId"],
    ["subject_label", "events", "subjectLabel"],
    ["summary", "events", "summary"],
    ["action_path", "events", "actionPath"],
    ["priority", "events", "priority"],
    ["resolved_at", "recipients", "resolvedAt"],
  ];
  for (const [key, table, logical] of optional) {
    if (n.has(table, logical)) {
      pairs.push([
        key,
        `${table === "events" ? "ev" : "rc"}.${n.col(table, logical)}`,
      ]);
    }
  }
  return `jsonb_build_object(${pairs.map(([key, value]) => `'${key}', ${value}`).join(", ")})`;
}
