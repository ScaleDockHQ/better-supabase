import type { ModuleContext } from "./context.ts";

import { sqlString } from "../core/template.ts";

/**
 * SQL that makes `user` watch a subject at the `participating` level through
 * the notifications module's subscriptions, keeping any level the user already
 * chose. Empty without notifications or its subscriptions table. Every
 * expression is SQL; `module` must integrate notifications.
 */
export function watchSql(
  ctx: ModuleContext,
  watch: {
    readonly tenant: string;
    readonly user: string;
    readonly subjectType: string;
    readonly subjectId: string;
  },
): string {
  if (!ctx.installed("notifications")) {
    return "";
  }

  const n = ctx.of("notifications");

  if (!n.hasTable("subscriptions")) {
    return "";
  }

  const s = (logical: string): string => n.col("subscriptions", logical);
  const tenanted = n.has("subscriptions", "tenant");

  const columns = [
    ...(tenanted ? [s("tenant")] : []),
    s("user"),
    s("subjectType"),
    s("subjectId"),
    s("level"),
  ];

  const values = [
    ...(tenanted ? [watch.tenant] : []),
    watch.user,
    watch.subjectType,
    watch.subjectId,
    "'participating'",
  ];

  return `insert into ${n.table("subscriptions")} (${columns.join(", ")})
    values (${values.join(", ")})
    on conflict do nothing;`;
}

/**
 * SQL that is true when a `notify` on a subject that names no recipients can
 * reach anyone: a follower of the subject at the `all` or `participating` level
 * who isn't in `exclude` (a `uuid[]` expression), or a `notification_audience`
 * hook that may add recipients. `false` without notifications. Every expression
 * is SQL; `module` must integrate notifications.
 */
export function followersSql(
  ctx: ModuleContext,
  watch: {
    readonly tenant: string;
    readonly subjectType: string;
    readonly subjectId: string;
    readonly exclude: string;
  },
): string {
  if (!ctx.installed("notifications")) {
    return "false";
  }

  const n = ctx.of("notifications");
  const audience = `to_regprocedure(${sqlString(`${n.hookTarget("notification_audience")}(jsonb)`)}) is not null`;

  const watched =
    n.hasTable("subscriptions") &&
    n.has("events", "subjectType") &&
    n.has("events", "subjectId");

  if (!watched) {
    return audience;
  }

  const s = (logical: string): string => n.col("subscriptions", logical);

  const tenant = n.has("subscriptions", "tenant")
    ? ` and s.${s("tenant")} = ${watch.tenant}`
    : "";

  return `(exists (
      select 1 from ${n.table("subscriptions")} s
      where s.${s("subjectType")} = ${watch.subjectType} and s.${s("subjectId")} = ${watch.subjectId}${tenant}
        and s.${s("level")} in ('all', 'participating')
        and not s.${s("user")} = any (${watch.exclude})
    ) or ${audience})`;
}
