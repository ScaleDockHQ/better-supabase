import type {
  JSONValue,
  LanguageModel,
  LanguageModelMiddleware,
  StopCondition,
  ToolApprovalStatus,
  ToolLoopAgentSettings,
  ToolSet,
} from "ai";

import { isStepCount, pruneMessages, ToolLoopAgent } from "ai";

import type { SessionActor } from "../../auth/actor.ts";
import type { Agent } from "../../blocks/agents/agents.ts";
import type {
  AiChat,
  AiModerationAction,
  AiModerationStage,
  AiToolPolicy,
} from "../../blocks/ai-chat/ai-chat.ts";
import type {
  Knowledge,
  KnowledgeHit,
  KnowledgeSearchOptions,
} from "../../blocks/knowledge/knowledge.ts";
import type { OperationTable } from "../../core/operations.ts";
import type {
  ResultsFilter,
  SearchToolOptions,
} from "../embeddings/embeddings.ts";
import type { GatewayOptions } from "../gateway-options.ts";
import type {
  AgentCaller,
  AgentModelAuthorizer,
  AgentResultsContext,
  AgentRunContext,
  AgentToolAuthorizer,
  AgentToolOperation,
  AgentToolOperations,
  AgentToolPermissions,
} from "./authorization.ts";

import { DbException } from "../../core/db-exception.ts";
import { searchTool } from "../embeddings/embeddings.ts";
import { gatewayOptions } from "../gateway-options.ts";
import {
  agentRunContext,
  agentToolOperation,
  assertModelAllowed,
  assertToolDelegated,
  toolDelegated,
  toolPermitted,
} from "./authorization.ts";

/**
 * The tools an agent may call: the ones it lists (every tool when it lists
 * none), without the tenant's `deny` tools and, when the session's `actor` is
 * an agent that lists tools, without the ones it wasn't delegated.
 */
export function agentTools(
  agent: Pick<Agent, "tools">,
  available: ToolSet,
  policies: Readonly<Record<string, AiToolPolicy>> = {},
  actor?: SessionActor,
): ToolSet {
  const allowed = agent.tools.length === 0 ? undefined : new Set(agent.tools);
  const tools: ToolSet = {};

  for (const [name, tool] of Object.entries(available)) {
    if (allowed !== undefined && !allowed.has(name)) {
      continue;
    }

    if (!toolDelegated(actor, name)) {
      continue;
    }

    const policy = policies[name];

    if (policy === "deny") {
      continue;
    }

    tools[name] = tool;
  }

  return tools;
}

/**
 * The `toolApproval` setting that makes the tenant's `ask` tools wait for the
 * user.
 */
export function agentToolApproval(
  tools: ToolSet,
  policies: Readonly<Record<string, AiToolPolicy>> = {},
): Record<string, "user-approval"> {
  const approval: Record<string, "user-approval"> = {};

  for (const name of Object.keys(tools)) {
    if (policies[name] === "ask") {
      approval[name] = "user-approval";
    }
  }

  return approval;
}

/** A `toolApproval` function, as `ToolLoopAgent` takes it. */
export type AgentToolApprovalFunction = Extract<
  NonNullable<ToolLoopAgentSettings<never, ToolSet>["toolApproval"]>,
  (options: never) => unknown
>;

const APPROVAL_RANK = {
  "not-applicable": 0,
  approved: 1,
  "user-approval": 2,
  denied: 3,
} as const;

const approvalType = (
  status: ToolApprovalStatus,
): keyof typeof APPROVAL_RANK =>
  status === undefined
    ? "not-applicable"
    : typeof status === "string"
      ? status
      : status.type;

interface ApprovalChecks {
  readonly actor: SessionActor | undefined;
  readonly approve: AgentToolApprovalFunction | undefined;
  /** The tenant's `ask` tools and the provider's high-risk ones. */
  readonly ask: Readonly<Record<string, "user-approval">>;
  readonly authorizeTool: AgentToolAuthorizer | undefined;
  readonly operation: (name: string) => AgentToolOperation;
  readonly run: AgentRunContext;
}

/**
 * The delegation check, the permission check, then the app's `toolApproval`,
 * then the `ask` tools: a tool the session's agent wasn't delegated or a
 * refused permission denies, and otherwise the stricter answer wins (`denied`,
 * then `user-approval`). A function that throws denies the call.
 */
function composedApproval(checks: ApprovalChecks): AgentToolApprovalFunction {
  return async (options) => {
    const { toolName } = options.toolCall;
    const input: unknown = options.toolCall.input;

    try {
      assertToolDelegated(checks.actor, toolName);
    } catch (error) {
      return {
        type: "denied",
        reason:
          error instanceof DbException
            ? error.error.message
            : "The tool was not delegated",
      };
    }

    if (checks.authorizeTool !== undefined) {
      const operation = checks.operation(toolName);

      const permitted = await toolPermitted(checks.authorizeTool, operation, {
        ...checks.run,
        toolName,
        operation: operation.operation,
        input,
      });

      if (!permitted) {
        return { type: "denied", reason: "The caller may not use this tool" };
      }
    }

    let status: ToolApprovalStatus = "not-applicable";

    if (checks.approve !== undefined) {
      try {
        status = await checks.approve(options);
      } catch {
        return { type: "denied", reason: "The tool approval check failed" };
      }
    }

    const asked = checks.ask[toolName] !== undefined;

    return asked &&
      APPROVAL_RANK[approvalType(status)] < APPROVAL_RANK["user-approval"]
      ? "user-approval"
      : status;
  };
}

/** The knowledge scopes an agent searches; `agent` without an id is its own. */
export function agentScopes(
  agent: Pick<Agent, "id" | "knowledgeScopes">,
): NonNullable<KnowledgeSearchOptions["scopes"]> {
  return agent.knowledgeScopes.map((scope) =>
    scope.scope === "agent" && scope.id === undefined
      ? { scope: "agent", id: agent.id }
      : scope,
  );
}

export interface AgentRuntimeOptions {
  readonly agent: Agent;
  /** The model for the agent's `model` id; the app picks one when it is unset. */
  readonly model: (modelId: string | undefined) => LanguageModel;
  /** Every tool the app offers; the agent gets the ones it may call. */
  readonly tools?: ToolSet;
  /** `approvals.policies(organizationId)` of the ai-chat block. */
  readonly policies?: Readonly<Record<string, AiToolPolicy>>;
  /** Adds a `search_knowledge` tool over the agent's knowledge scopes. */
  readonly knowledge?: {
    readonly knowledge: Knowledge;
    readonly organizationId: string;
    readonly options?: SearchToolOptions;
  };
  /** Text before the agent's own instructions, such as the app's rules. */
  readonly instructions?: string;
  /** Default 20 steps. */
  readonly stopWhen?: StopCondition<ToolSet> | StopCondition<ToolSet>[];
  /**
   * The app's approval check for each tool call. It runs after the permission
   * check and before the tenant's `policies`, and the stricter answer wins:
   * `denied` over `user-approval` over `approved`. A throw denies.
   */
  readonly toolApproval?: AgentToolApprovalFunction;
  /**
   * The user the agent runs for, from the verified session. It is the principal
   * of every check and the AI Gateway's `user`; the agent is only the actor.
   * For a run nobody invoked, pass the publishing user.
   */
  readonly caller?: AgentCaller;
  /**
   * The session's actor, from `actorOf(claims)`. When it is an agent whose
   * `act.tools` lists tools, the run gets only those, and a call to any other
   * is denied (`AGENT_TOOL_NOT_DELEGATED`). A read-only agent makes the run's
   * `act` read-only.
   */
  readonly actor?: SessionActor;
  /**
   * Called before every model call with the model id and the run context.
   * `false` or a throw refuses the run with a `forbidden` error before the
   * model is called. Every model is allowed without it.
   */
  readonly authorizeModel?: AgentModelAuthorizer;
  /**
   * Drops the knowledge hits the caller may not read, before the reranker,
   * `onHits` and the model see them.
   */
  readonly results?: ResultsFilter<KnowledgeHit, AgentResultsContext>;
  /**
   * The provider's operations (`authorization.operations`). An `ai.tool.<name>`
   * entry sets the tool's permission over `permissions`, and a `high` risk
   * makes the tool wait for the user's approval.
   */
  readonly operations?: OperationTable;
  /** Each tool's own permission; `false` marks a tool that needs none. */
  readonly permissions?: AgentToolPermissions;
  /** The provider operation each tool checks, in place of `ai.tool.<name>`. */
  readonly toolOperations?: AgentToolOperations;
  /**
   * Checks the caller's permission for each tool call. With it, a tool without
   * a permission (from `operations` or `permissions`) is denied, and so is a
   * check that returns `false` or throws.
   */
  readonly authorizeTool?: AgentToolAuthorizer;
  /**
   * AI Gateway attribution for every model call: the caller's id as `user`, and
   * the tenant, `feature` (default `agent`), `agent:<id>` and `tags` as tags.
   * `options` adds gateway options; a `user` in it is dropped.
   */
  readonly gateway?: {
    readonly feature?: string;
    readonly chatId?: string;
    readonly tags?: readonly string[];
    readonly options?: GatewayOptions;
  };
  /**
   * Telemetry for the agent's calls. The runtime sets `functionId`
   * (`agent:<id>`) and exposes the run's `organizationId` to the integrations,
   * so `meterTelemetry` can meter the tenant; what you pass wins.
   */
  readonly telemetry?: RuntimeSettings["telemetry"];
  /**
   * Signs tool approval requests (AI SDK 7 `experimental_toolApprovalSecret`),
   * so a client can't forge an approval.
   */
  readonly toolApprovalSecret?: string | Uint8Array;
  /** Other `ToolLoopAgent` settings, such as `toolCallConcurrency` or `output`. */
  readonly settings?: AgentPassthroughOptions;
  /**
   * Your `prepareCall`. It runs first; the library then merges its context and
   * the gateway attribution into what it returns.
   */
  readonly prepareCall?: RuntimeSettings["prepareCall"];
  /**
   * Your `prepareStep`. It runs after the library's model check; its result is
   * used, and its `messages` are pruned when `compact` is set.
   */
  readonly prepareStep?: RuntimeSettings["prepareStep"];
  /** Prunes old reasoning and tool calls from the messages of every step. */
  readonly compact?: AgentCompactOptions;
}

type RuntimeSettings = ToolLoopAgentSettings<never, ToolSet>;

/** `pruneMessages` options for a long chat, applied before every step. */
export type AgentCompactOptions = Omit<
  Parameters<typeof pruneMessages>[0],
  "messages"
>;

/**
 * `ToolLoopAgent` settings the runtime passes through. The library owns the
 * ones that carry its checks (`tools`, `toolApproval`, `runtimeContext`,
 * `instructions`, `stopWhen`, `id` and `model`).
 */
export type AgentPassthroughOptions = Omit<
  RuntimeSettings,
  | "id"
  | "model"
  | "tools"
  | "toolApproval"
  | "instructions"
  | "stopWhen"
  | "runtimeContext"
  | "prepareCall"
  | "prepareStep"
  | "telemetry"
  | "experimental_telemetry"
  | "experimental_toolApprovalSecret"
>;

type ProviderOptionsMap = NonNullable<
  ToolLoopAgentSettings<never, ToolSet>["providerOptions"]
>;

const stringTags = (value: JSONValue | undefined): string[] =>
  Array.isArray(value)
    ? value.filter((tag): tag is string => typeof tag === "string")
    : [];

/**
 * The library's `providerOptions.gateway` merged into the call's own: the
 * library's `user` always wins, `tags` are the union (library first), and every
 * other key, nested under `gateway` or under another provider, keeps the call's
 * value over the library's.
 */
export function mergeGatewayOptions(
  call: ProviderOptionsMap | undefined,
  library: { readonly gateway: GatewayOptions } | undefined,
): ProviderOptionsMap | undefined {
  if (library === undefined) {
    return call;
  }

  const own: Record<string, JSONValue | undefined> = call?.["gateway"] ?? {};
  const base: Record<string, JSONValue | undefined> = { ...library.gateway };

  for (const [key, value] of Object.entries(own)) {
    if (key === "tags" || (key === "user" && base["user"] !== undefined)) {
      continue;
    }

    base[key] = value;
  }

  const tags = [
    ...new Set([
      ...stringTags(library.gateway["tags"]),
      ...stringTags(own["tags"]),
    ]),
  ];

  if (tags.length > 0) {
    base["tags"] = tags;
  }

  return { ...call, gateway: base };
}

/** What `createAgentRuntime` and the workflow runtime share. */
export interface AgentRuntimeParts {
  readonly tools: ToolSet;
  /**
   * The tools the tenant's policy or the provider's risk makes wait for the
   * user.
   */
  readonly ask: Readonly<Record<string, "user-approval">>;
  readonly instructions: string;
  readonly run: AgentRunContext;
  readonly operation: (name: string) => AgentToolOperation;
  /** The tool-call check as `ToolLoopAgent`'s `toolApproval`. */
  readonly toolApproval:
    | AgentToolApprovalFunction
    | Record<string, "user-approval">;
  /** The call's `providerOptions` with the gateway attribution merged in. */
  readonly withGateway: (
    providerOptions: ProviderOptionsMap | undefined,
  ) => ProviderOptionsMap | undefined;
  /** Refuses the run when the app's model check says so. */
  readonly checkModel: (model: LanguageModel) => Promise<void>;
}

/** The tools, approvals, context and attribution of an agent row. */
export function agentRuntimeParts(
  options: AgentRuntimeOptions,
): AgentRuntimeParts {
  const { agent } = options;

  const tools = agentTools(
    agent,
    options.tools ?? {},
    options.policies,
    options.actor,
  );

  const searchesKnowledge =
    options.knowledge !== undefined &&
    agent.knowledgeScopes.length > 0 &&
    toolDelegated(options.actor, "search_knowledge");

  const run = agentRunContext(
    agent,
    options.caller,
    [...Object.keys(tools), ...(searchesKnowledge ? ["search_knowledge"] : [])],
    options.actor,
  );

  if (searchesKnowledge) {
    const {
      knowledge,
      organizationId,
      options: search = {},
    } = options.knowledge;

    const filter = options.results;
    tools["search_knowledge"] = searchTool(knowledge, organizationId, {
      ...search,
      scopes: agentScopes(agent),
      ...(filter === undefined
        ? {}
        : {
            results: (hits, { query }) =>
              filter(hits, { ...run, toolName: "search_knowledge", query }),
          }),
    });
  }

  const operation = (name: string): AgentToolOperation =>
    agentToolOperation(
      name,
      options.operations,
      options.permissions,
      options.toolOperations,
    );

  const ask: Record<string, "user-approval"> = {
    ...agentToolApproval(tools, options.policies),
  };

  for (const name of Object.keys(tools)) {
    if (operation(name).risk === "high") {
      ask[name] = "user-approval";
    }
  }

  const instructions = [options.instructions, agent.instructions]
    .filter((text) => text !== undefined && text !== "")
    .join("\n\n");

  const gateway =
    options.gateway === undefined && options.caller === undefined
      ? undefined
      : gatewayOptions(
          {
            ...(run.userId === undefined ? {} : { userId: run.userId }),
            ...(run.organizationId === undefined
              ? {}
              : { organizationId: run.organizationId }),
            ...(options.gateway?.chatId === undefined
              ? {}
              : { chatId: options.gateway.chatId }),
            feature: options.gateway?.feature ?? "agent",
            tags: [`agent:${agent.id}`, ...(options.gateway?.tags ?? [])],
          },
          options.gateway?.options,
        );

  const { authorizeModel } = options;

  return {
    tools,
    ask,
    instructions,
    run,
    operation,
    toolApproval:
      options.toolApproval === undefined &&
      options.authorizeTool === undefined &&
      options.actor === undefined
        ? ask
        : composedApproval({
            actor: options.actor,
            approve: options.toolApproval,
            ask,
            authorizeTool: options.authorizeTool,
            operation,
            run,
          }),
    withGateway: (providerOptions) =>
      mergeGatewayOptions(providerOptions, gateway),
    checkModel: async (model) => {
      if (authorizeModel !== undefined) {
        await assertModelAllowed(authorizeModel, model, run);
      }
    },
  };
}

/** A `ToolLoopAgent` from an agent row. */
export function createAgentRuntime(
  options: AgentRuntimeOptions,
): ToolLoopAgent<never, ToolSet> {
  const { agent } = options;
  const parts = agentRuntimeParts(options);
  const { run } = parts;

  const { prepareCall, prepareStep, compact } = options;

  return new ToolLoopAgent({
    ...options.settings,
    id: agent.id,
    model: options.model(agent.model),
    tools: parts.tools,
    toolApproval: parts.toolApproval,
    ...(parts.instructions === "" ? {} : { instructions: parts.instructions }),
    stopWhen: options.stopWhen ?? isStepCount(20),
    runtimeContext: run,
    telemetry: {
      functionId: `agent:${agent.id}`,
      includeRuntimeContext: { organizationId: true },
      ...options.telemetry,
    },
    ...(options.toolApprovalSecret === undefined
      ? {}
      : { experimental_toolApprovalSecret: options.toolApprovalSecret }),
    prepareCall: async (call) => {
      const own = prepareCall === undefined ? call : await prepareCall(call);
      const providerOptions = parts.withGateway(own.providerOptions);

      return {
        ...own,
        runtimeContext: { ...own.runtimeContext, ...run },
        ...(providerOptions === undefined ? {} : { providerOptions }),
      };
    },
    prepareStep: async (step) => {
      await parts.checkModel(step.model);

      const own = prepareStep === undefined ? {} : await prepareStep(step);

      if (compact === undefined) {
        return own;
      }

      return {
        ...own,
        messages: pruneMessages({
          ...compact,
          messages: [...(own?.messages ?? step.messages)],
        }),
      };
    },
  });
}

/** What a moderation check says about a text. */
export interface ModerationVerdict {
  readonly action: AiModerationAction;
  readonly category: string;
  readonly score?: number;
}

export interface ModerationMiddlewareOptions {
  readonly chats: AiChat;
  readonly organizationId: string;
  readonly chatId?: string;
  readonly userId?: string;
  /** Checks the last user message (`input`) and the answer (`output`). */
  readonly check: (
    text: string,
    stage: Extract<AiModerationStage, "input" | "output">,
  ) => Promise<ModerationVerdict | undefined>;
}

/** Thrown by the moderation middleware when a check blocks the input or output. */
export class ModerationBlockedError extends Error {
  readonly category: string;
  readonly stage: AiModerationStage;
  constructor(stage: AiModerationStage, category: string) {
    super(`The ${stage} was blocked by moderation (${category})`);
    this.name = "ModerationBlockedError";
    this.stage = stage;
    this.category = category;
  }
}

type Prompt = Parameters<
  NonNullable<LanguageModelMiddleware["transformParams"]>
>[0]["params"]["prompt"];

function lastUserText(prompt: Prompt): string {
  for (let index = prompt.length - 1; index >= 0; index -= 1) {
    const message = prompt[index];

    if (message?.role !== "user") {
      continue;
    }

    return message.content
      .flatMap((part) => (part.type === "text" ? [part.text] : []))
      .join("\n");
  }

  return "";
}

/**
 * A language model middleware that checks the user's message before the model
 * runs and the answer after it, records every verdict but `allow` in the
 * ai-chat moderation log, and throws `ModerationBlockedError` on `block`. A
 * streamed answer has reached the client when its check runs, so a blocked
 * stream ends with an error part instead of the text vanishing.
 */
export function moderationMiddleware(
  options: ModerationMiddlewareOptions,
): LanguageModelMiddleware {
  const judge = async (
    text: string,
    stage: "input" | "output",
  ): Promise<ModerationVerdict | undefined> => {
    if (text.trim() === "") {
      return undefined;
    }

    const verdict = await options.check(text, stage);

    if (verdict === undefined || verdict.action === "allow") {
      return verdict;
    }

    const recorded = await options.chats.moderation.record({
      event: {
        organizationId: options.organizationId,
        stage,
        action: verdict.action,
        category: verdict.category,
        ...(options.chatId === undefined ? {} : { chatId: options.chatId }),
        ...(options.userId === undefined ? {} : { userId: options.userId }),
        ...(verdict.score === undefined ? {} : { score: verdict.score }),
      },
    });

    if (!recorded.ok) {
      throw new DbException(recorded.error);
    }

    return verdict;
  };

  return {
    transformParams: async ({ params }) => {
      const verdict = await judge(lastUserText(params.prompt), "input");

      if (verdict?.action === "block") {
        throw new ModerationBlockedError("input", verdict.category);
      }

      return params;
    },
    wrapGenerate: async ({ doGenerate }) => {
      const result = await doGenerate();

      const text = result.content
        .flatMap((part) => (part.type === "text" ? [part.text] : []))
        .join("");

      const verdict = await judge(text, "output");

      if (verdict?.action === "block") {
        throw new ModerationBlockedError("output", verdict.category);
      }

      return result;
    },
    wrapStream: async ({ doStream }) => {
      const result = await doStream();
      let text = "";

      type Part =
        typeof result.stream extends ReadableStream<infer P> ? P : never;

      const checked = result.stream.pipeThrough(
        new TransformStream<Part, Part>({
          transform(part, controller) {
            if (part.type === "text-delta") {
              text += part.delta;
            }

            controller.enqueue(part);
          },
          async flush(controller) {
            const verdict = await judge(text, "output");

            if (verdict?.action === "block") {
              controller.enqueue({
                type: "error",
                error: new ModerationBlockedError("output", verdict.category),
              });
            }
          },
        }),
      );

      return { ...result, stream: checked };
    },
  };
}
