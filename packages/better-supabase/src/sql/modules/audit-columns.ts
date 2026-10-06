import type { ModuleContext } from "../context.ts";

export type AuditImpersonators = "show" | "hide";

/** `sql.modules.audit.options.impersonators`: whether tenant readers see who impersonated. */
export function impersonators(ctx: ModuleContext): AuditImpersonators {
  const value = ctx.text("impersonators", "show");
  if (value !== "show" && value !== "hide") {
    throw new TypeError(
      `sql.modules.audit.options.impersonators must be "show" or "hide", not "${value}"`,
    );
  }
  return value;
}

/**
 * Columns added in version 3. A managed table has them; an adopted one only
 * when `sql.modules.audit.columns` maps them, so existing configs keep
 * working.
 */
const ADDED_COLUMNS: Readonly<Record<string, readonly string[]>> = {
  log: [
    "actorKind",
    "actorLabel",
    "tenantLabel",
    "targetLabel",
    "summary",
    "requestId",
    "correlationId",
    "scope",
  ],
  restricted: ["sessionId", "changedValues"],
};

/** Whether the log or restricted table has a logical column. */
export function hasColumn(
  ctx: ModuleContext,
  table: string,
  logical: string,
): boolean {
  if (!ctx.has(table, logical)) return false;
  if (ctx.manages || !ADDED_COLUMNS[table]?.includes(logical)) return true;
  return typeof ctx.config.columns[table]?.[logical] === "string";
}
