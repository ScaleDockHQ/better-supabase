import type { ModuleContext } from "./context.ts";

/**
 * SQL that makes `user` watch a subject at the `participating` level
 * through the notifications module's subscriptions, keeping any level the
 * user already chose. Empty without notifications or its subscriptions
 * table. Every expression is SQL; `module` must integrate notifications.
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
