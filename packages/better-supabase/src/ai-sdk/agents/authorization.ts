import type { LanguageModel } from "ai";

import type { AgentActOptions } from "../../auth/actor.ts";
import type { Agent } from "../../blocks/agents/agents.ts";
import type { AuthorizationOperation } from "../../config/authorization.ts";

import { DbException } from "../../core/db-exception.ts";
import { dbError } from "../../core/errors.ts";
import {
  OPERATION_PREFIXES,
  operationMeta,
  operationPermission,
  type OperationTable,
} from "../../core/operations.ts";

/** Who runs an agent: the user from the verified session, never a model or tool value. */
export interface AgentCaller {
  readonly userId: string;
  /** The tenant of the run; the agent's own tenant when unset. */
  readonly organizationId?: string;
}

/** The agent as the actor of a run. It acts for the caller and is never the principal. */
export interface AgentActor {
  readonly kind: "agent";
  readonly id: string;
}

/**
 * Who a run is for. `userId` is the principal: the invoking user, or the
 * publishing user for a run nobody invoked. The agent only appears as
 * `actor`.
 */
export type AgentRunContext = {
  readonly userId: string | undefined;
  readonly organizationId: string | undefined;
  readonly actor: AgentActor;
  /**
   * The `act` level a tool's database calls carry, with the run's tools:
   * pass `agentClaims(claims, run.act)` to `asUser` or `forContext`, so a tool
   * writes as the user, with the agent recorded as the actor.
   */
  readonly act: AgentActOptions;
};

/** The run context for an agent row, its caller and the tools it may call, frozen. */
export function agentRunContext(
  agent: Pick<Agent, "id" | "organizationId">,
  caller?: AgentCaller,
  tools: readonly string[] = [],
): AgentRunContext {
  return Object.freeze({
    userId: caller?.userId,
    organizationId: caller?.organizationId ?? agent.organizationId,
    actor: Object.freeze({ kind: "agent", id: agent.id }),
    act: Object.freeze({ agent: agent.id, tools: Object.freeze([...tools]) }),
  });
}

/**
 * The permission each tool needs when the provider's operations name none:
 * a permission key, or `false` for a tool that is public by design.
 */
export type AgentToolPermissions = Readonly<Record<string, string | false>>;

/** The provider operation each tool checks, in place of `ai.tool.<name>`. */
export type AgentToolOperations = Readonly<Record<string, string>>;

/** The operation an AI tool is, with what the provider says about it. */
export interface AgentToolOperation {
  /** `ai.tool.<name>`. */
  readonly operation: string;
  /** The permission the tool needs; `false` when public, `undefined` when none is declared. */
  readonly permission: string | false | undefined;
  readonly risk?: NonNullable<AuthorizationOperation["meta"]>["risk"];
  readonly effects?: NonNullable<AuthorizationOperation["meta"]>["effects"];
  readonly title?: string;
}

/**
 * The operation of the tool `name`: the provider's entry for the tool's
 * operation (from `toolOperations`, default `ai.tool.<name>`) first, then
 * the tool's own permission from `permissions`.
 */
export function agentToolOperation(
  name: string,
  operations?: OperationTable,
  permissions: AgentToolPermissions = {},
  toolOperations: AgentToolOperations = {},
): AgentToolOperation {
  const operation =
    (Object.hasOwn(toolOperations, name) ? toolOperations[name] : undefined) ??
    `${OPERATION_PREFIXES.aiTool}${name}`;
  const own = Object.hasOwn(permissions, name) ? permissions[name] : undefined;
  const permission =
    operationPermission(
      operations,
      operation,
      typeof own === "string" ? own : undefined,
    ) ?? (own === false ? false : undefined);
  const meta = operationMeta(operations, operation);
  return {
    operation,
    permission,
    ...(meta?.risk === undefined ? {} : { risk: meta.risk }),
    ...(meta?.effects === undefined ? {} : { effects: meta.effects }),
    ...(meta?.title === undefined ? {} : { title: meta.title }),
  };
}

/** What `authorizeTool` gets with the permission. */
export type AgentToolCallContext = AgentRunContext & {
  readonly toolName: string;
  readonly operation: string;
  /** The model's arguments; treat them as untrusted input. */
  readonly input: unknown;
};

/** What the runtime's `results` filter gets with the items. */
export type AgentResultsContext = AgentRunContext & {
  readonly toolName: string;
  readonly query: string;
};

/** Decides whether the caller may run a model. */
export type AgentModelAuthorizer = (
  modelId: string,
  context: AgentRunContext,
) => boolean | PromiseLike<boolean>;

/** Decides whether the caller holds a tool's permission. */
export type AgentToolAuthorizer = (
  permission: string,
  context: AgentToolCallContext,
) => boolean | PromiseLike<boolean>;

/** The id `authorizeModel` gets: the string itself, or the model's `modelId`. */
function modelIdOf(model: LanguageModel): string {
  return typeof model === "string" ? model : model.modelId;
}

const refused = (modelId: string): DbException =>
  new DbException(
    dbError("forbidden", `The model ${modelId} is not allowed.`, {
      code: "AI_MODEL_NOT_ALLOWED",
    }),
  );

/** Throws a forbidden `DbException` unless `authorize` allows the model; a throw refuses. */
export async function assertModelAllowed(
  authorize: AgentModelAuthorizer,
  model: LanguageModel,
  context: AgentRunContext,
): Promise<void> {
  const modelId = modelIdOf(model);
  let allowed: unknown;
  try {
    allowed = await authorize(modelId, context);
  } catch {
    throw refused(modelId);
  }
  if (allowed !== true) {
    throw refused(modelId);
  }
}

/**
 * Whether the call may run as far as permissions go: a tool with no declared
 * permission is refused, a public one is allowed without a check, and a
 * check that throws refuses.
 */
export async function toolPermitted(
  authorize: AgentToolAuthorizer,
  operation: AgentToolOperation,
  context: AgentToolCallContext,
): Promise<boolean> {
  if (operation.permission === false) {
    return true;
  }
  if (operation.permission === undefined) {
    return false;
  }
  try {
    const permitted: unknown = await authorize(operation.permission, context);
    return permitted === true;
  } catch {
    return false;
  }
}
