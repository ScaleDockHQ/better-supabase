import type { AuthorizationOperation } from "../config/authorization.ts";

/** Operations by name, as `authorization.operations` or a module's own defaults. */
export type OperationTable = Readonly<Record<string, AuthorizationOperation>>;

/** The prefixes each module looks its operations up under. */
export const OPERATION_PREFIXES = {
  workflowNode: "workflow.node.",
  mcpTool: "mcp.tool.",
  aiTool: "ai.tool.",
  inboxCommand: "inbox.command.",
} as const;

/**
 * The permission operation `name` needs: the provider's entry first, then
 * `fallback` (the module's own key, already renamed through
 * `blocks.<module>.permissions`). `undefined` when neither names one,
 * which a caller treats as "no permission declared" and refuses unless the
 * operation is public by design.
 */
export function operationPermission(
  operations: OperationTable | undefined,
  name: string,
  fallback?: string,
): string | undefined {
  if (operations !== undefined && Object.hasOwn(operations, name)) {
    const permission = operations[name]?.permission;

    if (typeof permission === "string" && permission !== "") {
      return permission;
    }
  }

  return fallback;
}

/** The operation `name`'s `meta`, from the provider's table. */
export function operationMeta(
  operations: OperationTable | undefined,
  name: string,
): AuthorizationOperation["meta"] {
  if (operations === undefined || !Object.hasOwn(operations, name)) {
    return;
  }

  return operations[name]?.meta;
}
