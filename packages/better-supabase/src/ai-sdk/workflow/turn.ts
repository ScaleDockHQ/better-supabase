import type { ModelCallStreamPart } from "@ai-sdk/workflow";
import type { LanguageModelUsage, ModelMessage } from "ai";

import type {
  AiRunStatus,
  AiStoredMessageStatus,
} from "../../blocks/ai-chat/ai-chat.ts";
import type { AiMessage } from "../../blocks/ai-chat/message.ts";
import type { AiUsage, GatewayOptions } from "../gateway.ts";

import { usageOf } from "../gateway.ts";
import {
  fromModelMessages,
  type ModelApproval,
  type ModelSource,
} from "../messages.ts";

/** What `durableChat` starts the turn's workflow with. Every field is serializable. */
export interface DurableTurnInput {
  readonly chatId: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly model: string;
  /** The answer's id: every save of the turn updates this message. */
  readonly messageId: string;
  /** The stored user message the answer is saved under. */
  readonly parentId: string;
  /** The `ai_runs` row of the first segment, claimed before the start. */
  readonly runId: string;
  /** The first segment's stream: the World stream namespace and the stream store id. */
  readonly streamId: string;
  readonly messages: ModelMessage[];
  readonly providerOptions: { readonly gateway: GatewayOptions };
}

/** The hook payload that continues a turn once its approvals are decided. */
export interface DurableResume {
  /** The next segment's stream, claimed by the caller. */
  readonly streamId: string;
  /** The next segment's `ai_runs` row. */
  readonly runId: string;
}

/** The stop hook's payload. */
export interface DurableStop {
  readonly reason?: string;
}

/** What the agent function gets for one segment. */
export interface DurableAgentArgs {
  readonly chatId: string;
  /** The segment's `ai_runs` row, for progress in `ai_run_steps`. */
  readonly runId: string;
  readonly messages: ModelMessage[];
  /** The segment's World stream: pass it to `agent.stream({ writable })`. */
  readonly writable: WritableStream<ModelCallStreamPart>;
  readonly abortSignal: AbortSignal;
  readonly model: string;
  readonly providerOptions: { readonly gateway: GatewayOptions };
}

/** The part of a `WorkflowAgent.stream` result the turn reads. */
export interface DurableAgentResult {
  readonly messages: ModelMessage[];
  readonly steps: readonly {
    readonly sources?: readonly (ModelSource & { readonly type?: string })[];
    readonly providerMetadata?: unknown;
  }[];
  readonly totalUsage?: Partial<LanguageModelUsage>;
}

/** An approval the agent asked for, to record in `ai_tool_approvals`. */
export interface DurableApprovalRequest {
  readonly approvalId: string;
  readonly toolCallId: string;
  readonly toolName: string;
  readonly input: unknown;
  readonly signature?: string;
}

/** A decided approval, read back from the database. */
export interface DurableDecision {
  readonly approvalId: string;
  readonly approved: boolean;
  readonly reason?: string;
}

export interface DurableSaveInput {
  readonly chatId: string;
  readonly message: AiMessage;
  readonly parentId: string;
  readonly model: string;
  readonly runId: string;
  readonly status: AiStoredMessageStatus;
}

export interface DurableApprovalsInput {
  readonly chatId: string;
  readonly runId: string;
  readonly messageId: string;
  readonly requests: readonly DurableApprovalRequest[];
}

export interface DurableDecisionsInput {
  readonly chatId: string;
  readonly approvalIds: readonly string[];
}

export interface DurableReleaseInput {
  readonly chatId: string;
  readonly streamId: string;
  readonly organizationId: string;
  readonly status: AiRunStatus;
  readonly usage?: AiUsage;
  readonly error?: string;
}

interface DurableStepTypes {
  readonly save: { readonly input: DurableSaveInput; readonly output: void };
  readonly approvals: {
    readonly input: DurableApprovalsInput;
    readonly output: void;
  };
  readonly decisions: {
    readonly input: DurableDecisionsInput;
    readonly output: DurableDecision[];
  };
  readonly release: {
    readonly input: DurableReleaseInput;
    readonly output: void;
  };
}

export type DurableStepName = keyof DurableStepTypes;
export type DurableStepInput<K extends DurableStepName> =
  DurableStepTypes[K]["input"];
export type DurableStepOutput<K extends DurableStepName> =
  DurableStepTypes[K]["output"];

/** The database work of a turn (`durableSteps`), each run as a step. */
export type DurableStepCalls = {
  readonly [K in DurableStepName]: (
    input: DurableStepInput<K>,
  ) => Promise<DurableStepOutput<K>>;
};

/**
 * The app's one `"use step"` function: `(name, input) =>
 * runDurableStep(serviceChats(), name, input)`.
 */
export type DurableStep = <K extends DurableStepName>(
  name: K,
  input: DurableStepInput<K>,
) => Promise<DurableStepOutput<K>>;

/** A hook as `createHook` returns it: awaited once, or iterated for every payload. */
export type DurableHook<T> = PromiseLike<T> & AsyncIterable<T>;

/** What `durableTurn` runs on; the workflow passes the Workflow SDK's functions. */
export interface DurableTurnDeps {
  /** `getWorkflowMetadata().workflowRunId`. */
  readonly runId: string;
  /** `createHook`. */
  readonly createHook: <T>(options: {
    readonly token: string;
  }) => DurableHook<T>;
  /** `getWritable`. */
  readonly getWritable: (options: {
    readonly namespace: string;
  }) => WritableStream<ModelCallStreamPart>;
  /** Runs the agent for one segment: `(args) => agent.stream(args)`. */
  readonly agent: (args: DurableAgentArgs) => Promise<DurableAgentResult>;
  readonly step: DurableStep;
}

export interface DurableTurnResult {
  readonly status: AiRunStatus;
  readonly messageId: string;
  /** How many agent passes the turn took: one more for each wait on approvals. */
  readonly segments: number;
}

/** The token of the hook that stops a durable turn. */
export function durableStopToken(workflowRunId: string): string {
  return `ai-chat-stop:${workflowRunId}`;
}

/** The token of the hook that continues a turn after its approvals. */
export function durableTurnToken(workflowRunId: string): string {
  return `ai-chat-turn:${workflowRunId}`;
}

const STOPPED = Symbol("stopped");

function messageOf(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}

/** The approval requests in `messages` that `known` doesn't hold yet. */
function newRequests(
  messages: readonly ModelMessage[],
  known: ReadonlyMap<string, ModelApproval>,
): DurableApprovalRequest[] {
  const calls = new Map<string, { toolName: string; input: unknown }>();
  const requests: DurableApprovalRequest[] = [];
  for (const message of messages) {
    if (message.role !== "assistant" || typeof message.content === "string")
      continue;
    for (const part of message.content) {
      if (part.type === "tool-call")
        calls.set(part.toolCallId, {
          toolName: part.toolName,
          input: part.input,
        });
      else if (
        part.type === "tool-approval-request" &&
        !known.has(part.approvalId)
      ) {
        const call = calls.get(part.toolCallId);
        const { signature } = part;
        requests.push({
          approvalId: part.approvalId,
          toolCallId: part.toolCallId,
          toolName: call?.toolName ?? "",
          input: call?.input,
          ...(signature === undefined ? {} : { signature }),
        });
      }
    }
  }
  return requests;
}

function sourcesOf(result: DurableAgentResult): ModelSource[] {
  return result.steps.flatMap((step) => step.sources ?? []);
}

/**
 * One durable answer, inside a `"use workflow"` function. Each pass of the
 * agent writes one segment: a World stream namespace, claimed in `ai_runs`.
 * The answer is saved after each pass under `input.messageId`. When the
 * agent asks for approvals, they go to `ai_tool_approvals`, the segment is
 * released and the turn waits on its hook (`durableTurnToken`) for as long
 * as the decisions take; it reads them back from the database rather than
 * from the hook payload. The stop hook (`durableStopToken`) aborts it.
 */
export async function durableTurn(
  input: DurableTurnInput,
  deps: DurableTurnDeps,
): Promise<DurableTurnResult> {
  const abort = new AbortController();
  const stopped = Promise.resolve(
    deps.createHook<DurableStop>({ token: durableStopToken(deps.runId) }),
  ).then((): typeof STOPPED => {
    abort.abort();
    return STOPPED;
  });
  const turnHook = deps.createHook<DurableResume>({
    token: durableTurnToken(deps.runId),
  });
  const resumes = turnHook[Symbol.asyncIterator]();

  const historyLength = input.messages.length;
  const approvals = new Map<string, ModelApproval>();
  const sources: ModelSource[] = [];
  let conversation = input.messages;
  let segment: DurableResume = { streamId: input.streamId, runId: input.runId };
  let segments = 0;

  for (;;) {
    segments += 1;
    let status: AiRunStatus = "done";
    let error: string | undefined;
    let usage: AiUsage | undefined;
    let requests: DurableApprovalRequest[] = [];
    try {
      const result = await deps.agent({
        chatId: input.chatId,
        runId: segment.runId,
        messages: conversation,
        writable: deps.getWritable({ namespace: segment.streamId }),
        abortSignal: abort.signal,
        model: input.model,
        providerOptions: input.providerOptions,
      });
      conversation = result.messages;
      sources.push(...sourcesOf(result));
      requests = newRequests(conversation.slice(historyLength), approvals);
      usage = usageOf({
        totalUsage: result.totalUsage,
        providerMetadata: result.steps.at(-1)?.providerMetadata,
      });
    } catch (cause) {
      status = "error";
      error = messageOf(cause);
    }
    if (abort.signal.aborted) status = "stopped";
    if (status !== "done") requests = [];
    for (const request of requests)
      approvals.set(request.approvalId, {
        approvalId: request.approvalId,
        toolCallId: request.toolCallId,
        state: "requested",
      });

    await deps.step("save", {
      chatId: input.chatId,
      message: fromModelMessages(
        input.messageId,
        conversation.slice(historyLength),
        { sources, approvals: [...approvals.values()] },
      ),
      parentId: input.parentId,
      model: input.model,
      runId: segment.runId,
      status:
        status === "done"
          ? "complete"
          : status === "stopped"
            ? "aborted"
            : "error",
    });
    if (requests.length > 0)
      await deps.step("approvals", {
        chatId: input.chatId,
        runId: segment.runId,
        messageId: input.messageId,
        requests,
      });
    await deps.step("release", {
      chatId: input.chatId,
      streamId: segment.streamId,
      organizationId: input.organizationId,
      status,
      ...(usage === undefined ? {} : { usage }),
      ...(error === undefined ? {} : { error }),
    });
    if (requests.length === 0)
      return { status, messageId: input.messageId, segments };

    const waiting = requests.map((request) => request.approvalId);
    let decided: DurableDecision[] = [];
    let next: DurableResume | undefined;
    while (decided.length < waiting.length) {
      const signal = await Promise.race([resumes.next(), stopped]);
      if (signal === STOPPED || signal.done === true)
        return { status: "stopped", messageId: input.messageId, segments };
      next = signal.value;
      decided = await deps.step("decisions", {
        chatId: input.chatId,
        approvalIds: waiting,
      });
    }
    if (next === undefined)
      return { status: "error", messageId: input.messageId, segments };
    for (const decision of decided) {
      const known = approvals.get(decision.approvalId);
      if (known !== undefined)
        approvals.set(decision.approvalId, {
          ...known,
          state: decision.approved ? "approved" : "denied",
          ...(decision.reason === undefined ? {} : { reason: decision.reason }),
        });
    }
    conversation = [
      ...conversation,
      {
        role: "tool",
        content: decided.map((decision) => ({
          type: "tool-approval-response" as const,
          approvalId: decision.approvalId,
          approved: decision.approved,
          ...(decision.reason === undefined ? {} : { reason: decision.reason }),
        })),
      },
    ];
    segment = next;
  }
}
