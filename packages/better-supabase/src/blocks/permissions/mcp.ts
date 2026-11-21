import type { McpTool } from "../../mcp/mcp.ts";
import type { Permissions } from "./permissions.ts";

import { defineTool } from "../../mcp/mcp.ts";

export interface ExplainPermissionToolOptions {
  /** The permissions client the tool asks. */
  readonly permissions: Permissions;
  /** The tool's name. Default: `explain_permission`. */
  readonly name?: string;
}

const textArg = (args: unknown, key: string): string | undefined => {
  const entries: readonly (readonly [string, unknown])[] =
    typeof args === "object" && args !== null ? Object.entries(args) : [];

  const value: unknown = entries.find(([name]) => name === key)?.[1];

  return typeof value === "string" && value !== "" ? value : undefined;
};

/**
 * A read-only MCP tool that answers why a member does or doesn't hold a
 * permission key: the verdict, the roles, the keys that match and a reason.
 * Without `userId` it explains the caller. Pass it in `createMcp({ tools })`.
 * The SQL decides who may ask about whom, so the tool adds no check.
 */
export function explainPermissionTool(
  options: ExplainPermissionToolOptions,
): McpTool<never, never, never> {
  return defineTool({
    name: options.name ?? "explain_permission",
    title: "Explain a permission",
    description:
      "Says why a member holds or lacks one permission key: the verdict, the member's roles, the granted keys that match and a reason. Without userId it explains the caller.",
    inputSchema: {
      type: "object",
      properties: {
        key: {
          type: "string",
          description: "The permission key, such as tasks.write.",
        },
        userId: {
          type: "string",
          description: "The member to explain. Defaults to the caller.",
        },
      },
      required: ["key"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, idempotentHint: true },
    run(args: unknown, ctx) {
      const key = textArg(args, "key");

      if (key === undefined) {
        throw new TypeError("explain_permission needs a key");
      }

      const userId =
        textArg(args, "userId") ??
        (ctx.auth.kind === "user" ? ctx.auth.user.id : undefined);

      if (userId === undefined) {
        throw new TypeError("explain_permission needs a userId");
      }

      return options.permissions.explain({ userId, key }).orThrow();
    },
  });
}
