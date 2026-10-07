import type { ModuleContext } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

export function readers(ctx: ModuleContext, n: NotifyNames): string {
  const id = ctx.idType;
  const parts: string[] = [];
  if (ctx.hasTable("subscriptions")) {
    const s = (logical: string) => n.col("subscriptions", logical);
    const t = n.has("subscriptions", "tenant");
    const list = "list_notification_subscriptions";
    parts.push(`
create or replace function ${ctx.fn(list)}(tenant ${id} default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type', s.${s("subjectType")},
    'subject_id', s.${s("subjectId")},
    'level', s.${s("level")},
    'tenant', ${t ? `s.${s("tenant")}` : "null"},
    'created_at', s.${s("createdAt")}
  ) order by s.${s("createdAt")} desc, s.${s("id")}), '[]')
  from ${n.table("subscriptions")} s
  where s.${s("user")} = auth.uid()${
    t
      ? `
    and (${list}.tenant is null or s.${s("tenant")} = ${list}.tenant)`
      : ""
  }
    and (${list}.subject_type is null or s.${s("subjectType")} = ${list}.subject_type)
    and (${list}.subject_id is null or s.${s("subjectId")} = ${list}.subject_id)
$$;
revoke execute on function ${ctx.fn(list)}(${id}, text, text) from public, anon;
grant execute on function ${ctx.fn(list)}(${id}, text, text) to authenticated, service_role;`);
  }
  if (ctx.hasTable("preferences")) {
    const p = (logical: string) => n.col("preferences", logical);
    const t = n.has("preferences", "tenant");
    const list = "list_notification_preferences";
    parts.push(`
create or replace function ${ctx.fn(list)}(tenant ${id} default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p.${p("type")},
    'channel', p.${p("channel")},
    'enabled', p.${p("enabled")},
    'tenant', ${t ? `p.${p("tenant")}` : "null"}
  ) order by ${t ? `p.${p("tenant")} nulls first, ` : ""}p.${p("type")}, p.${p("channel")}), '[]')
  from ${n.table("preferences")} p
  where p.${p("user")} = auth.uid()${
    t
      ? `
    and (${list}.tenant is null or p.${p("tenant")} is null or p.${p("tenant")} = ${list}.tenant)`
      : ""
  }
$$;
revoke execute on function ${ctx.fn(list)}(${id}) from public, anon;
grant execute on function ${ctx.fn(list)}(${id}) to authenticated, service_role;`);
  }
  return parts.join("\n");
}
