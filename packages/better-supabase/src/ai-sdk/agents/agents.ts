import {
  type LanguageModel,
  type LanguageModelMiddleware,
  type StopCondition,
  stepCountIs,
  type ToolApprovalStatus,
  ToolLoopAgent,
  type ToolLoopAgentSettings,
  type ToolSet,
} from "ai";

import type { Agent } from "../../blocks/agents/agents.ts";
import type {
  AiChat,
  AiModerationAction,
  AiModerationStage,
  AiToolPolicy,
} from "../../blocks/ai-chat/ai-chat.ts";
import type {
  Knowledge,
  KnowledgeSearchOptions,
} from "../../blocks/knowledge/knowledge.ts";

import { DbException } from "../../core/db-exception.ts";
import {
  searchTool,
  type SearchToolOptions,
} from "../embeddings/embeddings.ts";

/**
 * The tools an agent may call: the ones it lists (every tool when it lists
 * none), without the tenant's `deny` tools.
 */
export function agentTools(
  agent: Pick<Agent, "tools">,
  available: ToolSet,
  policies: Readonly<Record<string, AiToolPolicy>> = {},
): ToolSet {
  const allowed = agent.tools.length === 0 ? undefined : new Set(agent.tools);
  const tools: ToolSet = {};
  for (const [name, tool] of Object.entries(available)) {
    if (allowed !== undefined && !allowed.has(name)) continue;
    const policy = policies[name];
    if (policy === "deny") continue;
    tools[name] = tool;
  }
  return tools;
}

/** The `toolApproval` setting that makes the tenant's `ask` tools wait for the user. */
export function agentToolApproval(
  tools: ToolSet,
  policies: Readonly<Record<string, AiToolPolicy>> = {},
): Record<string, "user-approval"> {
  const approval: Record<string, "user-approval"> = {};
  for (const name of Object.keys(tools)) {
    if (policies[name] === "ask") approval[name] = "user-approval";
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

/**
 * The app's `toolApproval` with the tenant's `ask` tools: the app decides
 * first, and the stricter of the two answers wins (`denied`, then
 * `user-approval`). A function that throws denies the call.
 */
function composedApproval(
  approve: AgentToolApprovalFunction,
  tenant: Readonly<Record<string, "user-approval">>,
): AgentToolApprovalFunction {
  return async (options) => {
    let status: ToolApprovalStatus;
    try {
      status = await approve(options);
    } catch {
      return { type: "denied", reason: "The tool approval check failed" };
    }
    const asked = tenant[options.toolCall.toolName] !== undefined;
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
   * The app's approval check for each tool call, such as an authorization
   * check. It runs before the tenant's `policies`, and the stricter answer
   * wins: `denied` over `user-approval` over `approved`. A throw denies.
   */
  readonly toolApproval?: AgentToolApprovalFunction;
}

/** A `ToolLoopAgent` from an agent row. */
export function createAgentRuntime(
  options: AgentRuntimeOptions,
): ToolLoopAgent<never, ToolSet> {
  const { agent } = options;
  const tools = agentTools(agent, options.tools ?? {}, options.policies);
  if (options.knowledge !== undefined && agent.knowledgeScopes.length > 0) {
    const {
      knowledge,
      organizationId,
      options: search = {},
    } = options.knowledge;
    tools["search_knowledge"] = searchTool(knowledge, organizationId, {
      ...search,
      scopes: agentScopes(agent),
    });
  }
  const instructions = [options.instructions, agent.instructions]
    .filter((text) => text !== undefined && text !== "")
    .join("\n\n");
  return new ToolLoopAgent({
    id: agent.id,
    model: options.model(agent.model),
    tools,
    toolApproval:
      options.toolApproval === undefined
        ? agentToolApproval(tools, options.policies)
        : composedApproval(
            options.toolApproval,
            agentToolApproval(tools, options.policies),
          ),
    ...(instructions === "" ? {} : { instructions }),
    stopWhen: options.stopWhen ?? stepCountIs(20),
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
    if (message?.role !== "user") continue;
    return message.content
      .flatMap((part) => (part.type === "text" ? [part.text] : []))
      .join("\n");
  }
  return "";
}

/**
 * A language model middleware that checks the user's message before the
 * model runs and the answer after it, records every verdict but `allow` in
 * the ai-chat moderation log, and throws `ModerationBlockedError` on
 * `block`. A streamed answer has reached the client when its check runs, so
 * a blocked stream ends with an error part instead of the text vanishing.
 */
export function moderationMiddleware(
  options: ModerationMiddlewareOptions,
): LanguageModelMiddleware {
  const judge = async (
    text: string,
    stage: "input" | "output",
  ): Promise<ModerationVerdict | undefined> => {
    if (text.trim() === "") return undefined;
    const verdict = await options.check(text, stage);
    if (verdict === undefined || verdict.action === "allow") return verdict;
    const recorded = await options.chats.moderation.record({
      organizationId: options.organizationId,
      stage,
      action: verdict.action,
      category: verdict.category,
      ...(options.chatId === undefined ? {} : { chatId: options.chatId }),
      ...(options.userId === undefined ? {} : { userId: options.userId }),
      ...(verdict.score === undefined ? {} : { score: verdict.score }),
    });
    if (!recorded.ok) throw new DbException(recorded.error);
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
            if (part.type === "text-delta") text += part.delta;
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
