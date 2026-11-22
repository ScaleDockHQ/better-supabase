import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AiToolPolicy } from "../blocks/ai-chat/ai-chat.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { AsyncResult } from "../core/result.ts";
import type {
  EveApprovalConfiguration,
  EveApprovalContext,
  EveApprovalPolicy,
  EveApprovalStatus,
  EveSessionAuth,
  EveToolApproval,
  EveToolContext,
} from "./types.ts";

import { agentClaims } from "../auth/actor.ts";
import { DbException, dbError } from "../core/errors.ts";

/** The user a tool runs as when the session has no Supabase user. */
export interface EveRunAs {
  readonly userId: string;
  readonly tenant?: string;
}

/** Options for `eveContext`. */
export interface EveContextOptions {
  /** The agent the `act` claim names, such as the eve app's name. */
  readonly agent: string;
  /** The tools the agent may call. Leave it out for every tool. */
  readonly tools?: readonly string[];
  /** Writes `read_only: true`, so `actor_may_write()` refuses the writes. */
  readonly readOnly?: boolean;
  /**
   * The `scope` claim: the permission keys (or OAuth scopes mapped in
   * `blocks.permissions.scopes`) the agent may use for the user, such as
   * `["tasks.*"]`. An agent token holds no key the access functions check
   * unless a scope grants it, so leave it out only for tools whose policies ask
   * none of them. `["*"]` lends the agent every key the user holds.
   */
  readonly scopes?: readonly string[];
  /**
   * The permission key (or keys) the tool needs, such as `"tasks.write"`. It
   * joins `scopes`, so the agent token holds exactly the keys the tool's
   * policies check and a tool never names a scope twice.
   */
  readonly permission?: string | readonly string[];
  /**
   * The user to run as when the principal is not a Supabase user, such as an
   * inbox contact or a scheduled run's app principal. A function decides per
   * principal; `undefined` refuses it.
   */
  readonly runAs?:
    | EveRunAs
    | ((auth: EveSessionAuth | null) => EveRunAs | undefined);
  /** The `authenticator` a user principal needs. Default: `"supabase"`. */
  readonly authenticator?: string;
}

const tenantAttribute = (
  auth: EveSessionAuth | null | undefined,
): string | undefined => {
  const tenant = auth?.attributes["tenantId"];

  return typeof tenant === "string" && tenant !== "" ? tenant : undefined;
};

const scopesOf = (options: EveContextOptions): string[] | undefined => {
  if (options.scopes === undefined && options.permission === undefined) {
    return undefined;
  }

  const permission =
    options.permission === undefined
      ? []
      : typeof options.permission === "string"
        ? [options.permission]
        : options.permission;

  return [...new Set([...(options.scopes ?? []), ...permission])];
};

/**
 * The `RequestContext` for the session's principal: a Supabase user principal
 * becomes the user, with `tenantId` as the tenant and the agent as the outer
 * `act` level (`agentClaims`), so `forContext` runs the agent's calls under
 * row-level security with the agent narrowing. Any other principal throws a
 * `forbidden` `DbException`, unless `runAs` names the user to run as.
 */
export function eveContext(
  auth: EveSessionAuth | null | undefined,
  options: EveContextOptions,
): RequestContext {
  const principal = auth ?? null;
  const authenticator = options.authenticator ?? "supabase";

  const user =
    principal?.principalType === "user" &&
    principal.authenticator === authenticator &&
    principal.principalId !== ""
      ? { userId: principal.principalId, tenant: tenantAttribute(principal) }
      : typeof options.runAs === "function"
        ? options.runAs(principal)
        : options.runAs;

  if (user === undefined) {
    throw new DbException(
      dbError(
        "forbidden",
        `eve: a ${principal?.principalType ?? "missing"} principal has no Supabase user; pass runAs to run its tools`,
        { hint: "EVE_NO_USER" },
      ),
    );
  }

  const scopes = scopesOf(options);

  const claims = agentClaims(
    {
      sub: user.userId,
      ...(user.tenant === undefined ? {} : { tenant_id: user.tenant }),
      ...(scopes === undefined ? {} : { scope: scopes }),
    },
    {
      agent: options.agent,
      ...(options.tools === undefined ? {} : { tools: options.tools }),
      ...(options.readOnly === undefined ? {} : { readOnly: options.readOnly }),
    },
  );

  return {
    actor: { id: user.userId, kind: "user" },
    ...(user.tenant === undefined ? {} : { tenant: user.tenant }),
    claims,
  };
}

/** The part of `createServer` the eve tools call. */
export interface EveContextRunner<D> {
  forContext(
    context: RequestContext,
    options?: {
      readonly permissions?: readonly string[];
      readonly reason?: string;
    },
  ): AsyncResult<D>;
}

/** Where the tenants' tool policies come from, such as `chats.approvals`. */
export interface EveToolPolicySource {
  policies(
    organizationId: string,
  ): AsyncResult<Readonly<Record<string, AiToolPolicy>>>;
}

/** What `supabaseTool`'s `execute` receives next to the input. */
export interface SupabaseToolCall<D> {
  /** The repositories and blocks, as the session's user with the agent claim. */
  readonly db: D;
  /** The context `db` runs in. */
  readonly context: RequestContext;
  /** Eve's tool context. */
  readonly ctx: EveToolContext;
}

/** Options for `supabaseTool`. */
export interface SupabaseToolOptions<
  S extends StandardSchemaV1,
  D,
  O,
> extends EveContextOptions {
  readonly server: EveContextRunner<D>;
  readonly description: string;
  readonly inputSchema: S;
  /** Narrows the call to these permission keys (`forContext({ permissions })`). */
  readonly permissions?: readonly string[];
  /** The tool's own approval, such as `approvalPolicy()`. */
  readonly approval?: EveToolApproval;
  /**
   * The tenants' `auto`, `ask` and `deny` policies, keyed by tool name: `deny`
   * refuses the call and `ask` waits for a person, as `agentTools` and
   * `agentToolApproval` do for AI SDK agents.
   */
  readonly policies?: EveToolPolicySource;
  execute(
    input: StandardSchemaV1.InferOutput<S>,
    call: SupabaseToolCall<D>,
  ): O | Promise<O>;
}

/** The tool definition `supabaseTool` returns, for eve's `defineTool`. */
export interface SupabaseToolDefinition<S extends StandardSchemaV1, O> {
  readonly description: string;
  readonly inputSchema: S;
  readonly approval?: EveToolApproval;
  execute(
    input: StandardSchemaV1.InferOutput<S>,
    ctx: EveToolContext,
  ): Promise<O>;
}

const RANK = {
  "not-applicable": 0,
  approved: 1,
  "user-approval": 2,
  denied: 3,
} as const;

const rankOf = (status: EveApprovalStatus): number => {
  if (status === undefined || status === false) {
    return RANK["not-applicable"];
  }

  if (status === true) {
    return RANK["user-approval"];
  }

  return RANK[typeof status === "string" ? status : status.type];
};

/**
 * An approval policy for the tenants' tool policies: `deny` refuses the call,
 * `ask` waits for a person and `auto` leaves it to `inner`. The stricter of the
 * two wins. A session without a tenant falls through to `inner`.
 */
export function tenantToolApproval(
  source: EveToolPolicySource,
  inner?: EveApprovalPolicy,
): EveApprovalPolicy {
  return async (ctx: EveApprovalContext): Promise<EveApprovalStatus> => {
    const tenant = tenantAttribute(ctx.session.auth.current);

    const policy =
      tenant === undefined
        ? undefined
        : (await source.policies(tenant).orThrow())[ctx.toolName];

    const own: EveApprovalStatus =
      policy === "deny"
        ? { type: "denied", reason: "Your organization turned this tool off." }
        : policy === "ask"
          ? "user-approval"
          : "not-applicable";

    if (rankOf(own) === RANK.denied || inner === undefined) {
      return own;
    }

    const theirs = await inner(ctx);

    return rankOf(theirs) >= rankOf(own) ? theirs : own;
  };
}

const configOf = (approval: EveToolApproval): EveApprovalConfiguration =>
  typeof approval === "function" ? { request: approval } : approval;

/**
 * Combines approval policies for one tool: the strictest request result wins
 * (`denied`, then `user-approval`, then `approved`, then `not-applicable`; on a
 * tie the earlier policy's answer, with its reason, is kept) and every policy's
 * `response` must allow the answer, the first rejection winning. A policy
 * function has no `response` and allows it. The prompt is the first one a
 * policy defines. Use it to stack a tenant's rules on a tool's own.
 */
export function strictestApproval(
  ...policies: readonly EveToolApproval[]
): EveApprovalConfiguration {
  const configs = policies.map(configOf);
  const prompt = configs.find((config) => config.prompt !== undefined)?.prompt;

  return {
    ...(prompt === undefined ? {} : { prompt }),
    async request(ctx) {
      let strictest: EveApprovalStatus;

      for (const config of configs) {
        const status = await config.request(ctx);

        if (rankOf(status) > rankOf(strictest)) {
          strictest = status;
        }

        if (rankOf(strictest) === RANK.denied) {
          break;
        }
      }

      return strictest;
    },
    async response(ctx) {
      for (const config of configs) {
        const decision = await config.response?.(ctx);

        if (decision?.status === "rejected") {
          return decision;
        }
      }

      return { status: "allowed" };
    },
  };
}

const withPolicies = (
  approval: EveToolApproval | undefined,
  source: EveToolPolicySource | undefined,
): EveToolApproval | undefined => {
  if (source === undefined) {
    return approval;
  }

  if (approval === undefined || typeof approval === "function") {
    return tenantToolApproval(source, approval);
  }

  const config: EveApprovalConfiguration = {
    ...approval,
    request: tenantToolApproval(source, approval.request),
  };

  return config;
};

/**
 * An eve tool whose `execute` gets the repositories as the session's user,
 * through `server.forContext(eveContext(...))`, so every call runs under
 * row-level security with the agent's `act` claim. Pass the result to eve's
 * `defineTool`. A `Result` error from `forContext` throws a `DbException` here;
 * `execute` throws its own the same way, with `.orThrow()`.
 */
export function supabaseTool<S extends StandardSchemaV1, D, O>(
  options: SupabaseToolOptions<S, D, O>,
): SupabaseToolDefinition<S, O> {
  const approval = withPolicies(options.approval, options.policies);

  return {
    description: options.description,
    inputSchema: options.inputSchema,
    ...(approval === undefined ? {} : { approval }),
    async execute(input, ctx) {
      const context = eveContext(ctx.session.auth.current, options);

      const db = await options.server
        .forContext(context, {
          reason: "eve",
          ...(options.permissions === undefined
            ? {}
            : { permissions: options.permissions }),
        })
        .orThrow();

      return options.execute(input, { db, context, ctx });
    },
  };
}
