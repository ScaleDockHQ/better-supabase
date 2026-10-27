import type { AuthState } from "../auth/resolve.ts";
import type {
  AnyAuthorizer,
  AuthorizationPurpose,
  AuthorizerRuntime,
} from "../core/authorizer.ts";
import type { DbError } from "../core/errors.ts";
import type { OperationTable } from "../core/operations.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Result } from "../core/result.ts";

import {
  checkEach,
  checkPermission,
  isRequestMemo,
} from "../core/authorizer.ts";
import { dbError } from "../core/errors.ts";
import { OPERATION_PREFIXES, operationPermission } from "../core/operations.ts";
import { ok } from "../core/result.ts";
import { hasRole } from "../server/kit.ts";

/** `McpOptions.requiredRoles`: the roles, or the roles and the claim to read. */
export type RequiredRoles =
  | readonly string[]
  | { readonly roles: readonly string[]; readonly claim?: string };

/** The refusal for a caller without one of `required`'s roles. */
export function missingRole(
  auth: AuthState,
  required: RequiredRoles | undefined,
): DbError | undefined {
  if (!required || auth.kind === "secret") {
    return undefined;
  }

  const { roles, claim } =
    "roles" in required ? required : { roles: required, claim: undefined };

  if (roles.length === 0 || hasRole(auth, roles, claim)) {
    return undefined;
  }

  return dbError(
    "forbidden",
    `This server needs the role ${roles.join(" or ")}`,
    { code: "MISSING_ROLE" },
  );
}

/**
 * The permission a tool needs: the provider's entry for the tool's `operation`
 * (default `mcp.tool.<name>`) first, then the tool's own `permission`.
 */
export function toolPermission(
  operations: OperationTable | undefined,
  name: string,
  declared: unknown,
  operation: string = `${OPERATION_PREFIXES.mcpTool}${name}`,
): unknown {
  return (
    operationPermission(
      operations,
      operation,
      typeof declared === "string" ? declared : undefined,
    ) ?? declared
  );
}

/** The hint that makes a tool a read. */
interface ToolHints {
  readonly annotations?: { readonly readOnlyHint?: boolean };
}

/** A tool as the authorizer sees it. */
export interface PermissionGate {
  readonly name: string;
  /** The tool's `permission`; a tool without one is not checked here. */
  readonly permission?: unknown;
  readonly info?: ToolHints;
}

/** A tool's purpose: `readOnlyHint` makes it a read. */
function toolPurpose(info: ToolHints | undefined): AuthorizationPurpose {
  return {
    operation: "tool",
    intent: info?.annotations?.readOnlyHint === true ? "read" : "write",
  };
}

/** The context's memo as the authorizer runtime, when it has one. */
function runtimeOf(
  context: RequestContext | undefined,
): AuthorizerRuntime | undefined {
  return isRequestMemo(context?.memo) ? { memo: context.memo } : undefined;
}

/** The context of a `tools/call` or `tools/list` request, if the client has one. */
export function contextOf(db: unknown): RequestContext | undefined {
  if (typeof db !== "object" || db === null || !("$context" in db)) {
    return;
  }

  // SAFETY: `$context` on a connected client is the request's RequestContext.
  return db.$context as RequestContext | undefined;
}

/** The tool's name and permission, as the authorizer sees them. */
export interface CheckedTool {
  readonly info: { readonly name: string } & ToolHints;
  readonly permission?: unknown;
}

/**
 * Checks a tool call as the caller of `db`: the tool is the resource, its
 * arguments its properties. A tool without a permission passes.
 */
export async function checkTool(
  authorizer: AnyAuthorizer | undefined,
  tool: CheckedTool,
  args: unknown,
  db: unknown,
): Promise<Result<void>> {
  if (tool.permission === undefined) {
    return ok(undefined);
  }

  const isObject =
    typeof args === "object" && args !== null && !Array.isArray(args);

  // SAFETY: a non-array object is a JSON object of arguments.
  const properties = isObject
    ? (args as Readonly<Record<string, unknown>>)
    : undefined;

  const context = contextOf(db);
  const runtime = runtimeOf(context);

  return checkPermission({
    authorizer,
    permission: tool.permission,
    resource: {
      type: "mcp_tool",
      id: tool.info.name,
      ...(properties ? { properties, source: "input" } : {}),
    },
    context,
    ...toolPurpose(tool.info),
    ...(runtime ? { runtime } : {}),
  });
}

/**
 * Which tools the caller may see, in `tools` order: one batch per permission,
 * and a tool without a permission is always shown.
 */
export async function permittedTools(
  authorizer: AnyAuthorizer | undefined,
  tools: readonly PermissionGate[],
  context: RequestContext | undefined,
): Promise<readonly boolean[]> {
  const shown = tools.map((tool) => tool.permission === undefined);

  const groups = new Map<
    string,
    { permission: unknown; purpose: AuthorizationPurpose; indexes: number[] }
  >();

  for (const [index, tool] of tools.entries()) {
    if (tool.permission === undefined || !authorizer) {
      continue;
    }

    let key: string;

    try {
      key = authorizer.key(tool.permission);
    } catch {
      continue;
    }

    const purpose = toolPurpose(tool.info);
    const groupKey = `${purpose.intent ?? ""} ${key}`;

    const group = groups.get(groupKey) ?? {
      permission: tool.permission,
      purpose,
      indexes: [],
    };

    group.indexes.push(index);
    groups.set(groupKey, group);
  }

  await Promise.all(
    [...groups.values()].map(async ({ permission, purpose, indexes }) => {
      const granted = await checkEach(
        authorizer,
        permission,
        indexes.map((index) => ({ type: "mcp_tool", id: tools[index]!.name })),
        context,
        runtimeOf(context),
        purpose,
      );

      for (const [position, index] of indexes.entries()) {
        shown[index] = granted[position] ?? false;
      }
    }),
  );

  return shown;
}
