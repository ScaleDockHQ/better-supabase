import type {
  FinishReason,
  LanguageModelUsage,
  ModelMessage,
  TextStreamPart,
  ToolSet,
  UIMessage,
  UIMessageChunk,
  UIMessageStreamOnEndCallback,
  UIMessageStreamOptions,
} from "ai";

import {
  convertToModelMessages,
  isToolUIPart,
  JsonToSseTransformStream,
  safeValidateUIMessages,
  toUIMessageStream,
} from "ai";

import type {
  AiChat,
  AiChatRecord,
  AiModerationAction,
  AiRunStatus,
  AiUserMessageTrigger,
} from "../../blocks/ai-chat/ai-chat.ts";
import type { AiMessage } from "../../blocks/ai-chat/message.ts";
import type { AiStoredMessage } from "../../blocks/ai-chat/records.ts";
import type { DbError } from "../../core/errors.ts";
import type { StreamStore } from "../../streams/store.ts";
import type {
  AiUsage,
  CostBackfillPayload,
  GatewayOptions,
} from "../gateway.ts";

import {
  pathToHistory,
  repairDanglingToolCalls,
} from "../../blocks/ai-chat/history.ts";
import { isRecord } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { resumeFromStore, teeToStore } from "../../streams/tee.ts";
import { aiErrorMessage, aiErrorToDbError } from "../errors.ts";
import { gatewayOptions, problem429, runRelease, usageOf } from "../gateway.ts";
import { badRequest, readJson, sse } from "../http.ts";
import {
  AI_SDK_UI_FORMAT,
  fromUIMessage,
  isUIMessage,
  toUIMessage,
  toUIMessages,
} from "../messages.ts";

/** Who asks, for one request. */
export interface AssistantContext {
  /**
   * The chat block for this request: the user's transport, and a service
   * transport (`service`) for the writes only the server makes.
   */
  readonly chats: AiChat;
  readonly userId: string;
  /**
   * The tenant a new chat is made in; `null` for a chat outside a tenant
   * (`blocks.ai-chat.options.tenant: false`).
   */
  readonly organizationId: string | null;
  /**
   * Keeps the function alive until the answer is stored, after the response is
   * sent: `after` in Next.js, `ctx.waitUntil` on Workers and Vercel.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/** What `run` gets to generate one answer. */
export interface AssistantRunOptions<UI_MESSAGE extends UIMessage = UIMessage> {
  readonly chat: AiChatRecord;
  /** The model the request may use, after the catalog check. */
  readonly model: string;
  readonly messages: ModelMessage[];
  /** The history the model sees, as UI messages. */
  readonly uiMessages: UI_MESSAGE[];
  /** Aborted by `stop()`; pass it to `streamText` or `agent.stream`. */
  readonly abortSignal: AbortSignal;
  /** Spend attribution for the AI Gateway (`gatewayOptions`). */
  readonly providerOptions: { readonly gateway: GatewayOptions };
  /**
   * The app's `toolApprovalSecret`, for `experimental_toolApprovalSecret` of
   * `streamText` or the agent, so a replayed approval is verified.
   */
  readonly toolApprovalSecret?: string | Uint8Array;
  /**
   * The assistant message this turn continues after a tool approval,
   * `undefined` for a new user turn.
   */
  readonly continuationOf?: string;
  readonly context: AssistantContext;
}

/** The options the assistant passes to `toUIMessageStream`. */
interface UIStreamOptions<
  UI_MESSAGE extends UIMessage,
> extends AssistantStreamOptions<UI_MESSAGE> {
  originalMessages: UI_MESSAGE[];
  generateMessageId: () => string;
  onEnd: UIMessageStreamOnEndCallback<UI_MESSAGE>;
  onError?: (error: unknown) => string;
}

/**
 * The part of a `streamText` or `agent.stream` result the assistant reads. A
 * result of `streamText({ experimental_streamTextLowMemory: true })` fits too;
 * it has no `finalStep`, so the gateway's cost and generation id stay unknown.
 */
export interface AssistantRunResult {
  /** The full stream; the assistant turns it into UI message chunks. */
  readonly stream?: ReadableStream<TextStreamPart<ToolSet>>;
  /** The usage of every step together. */
  readonly usage?: PromiseLike<LanguageModelUsage>;
  /** The last step, whose `providerMetadata` carries the gateway's cost. */
  readonly finalStep?: PromiseLike<{ readonly providerMetadata?: unknown }>;
  /**
   * The tools of the run. `toUIMessageStream` reads them to mark a call
   * `dynamic` and to set its `title`, so pass `agent.tools` or the `streamText`
   * tools.
   */
  readonly tools?: ToolSet;
}

/** The verdict of a moderation hook. */
export interface AssistantModeration {
  readonly action: AiModerationAction;
  readonly category: string;
  readonly score?: number;
}

/** What `onFinish` gets once the answer is stored. */
export interface AssistantFinish<UI_MESSAGE extends UIMessage = UIMessage> {
  readonly chat: AiChatRecord;
  readonly message: UI_MESSAGE;
  readonly status: AiRunStatus;
  readonly model: string;
  readonly usage: AiUsage | undefined;
  readonly context: AssistantContext;
}

/**
 * The `toUIMessageStream` options an app may set: what the client receives
 * beside the text. `originalMessages`, `generateMessageId` and the end
 * callbacks stay with the assistant, which stores the answer.
 */
export type AssistantStreamOptions<UI_MESSAGE extends UIMessage = UIMessage> =
  Pick<
    UIMessageStreamOptions<UI_MESSAGE>,
    | "messageMetadata"
    | "sendReasoning"
    | "sendSources"
    | "sendStart"
    | "sendFinish"
  >;

/**
 * The schemas `safeValidateUIMessages` checks the user's message against before
 * it is stored. A message that fails answers 422.
 */
export type AssistantValidation<UI_MESSAGE extends UIMessage = UIMessage> =
  Pick<
    Parameters<typeof safeValidateUIMessages<UI_MESSAGE>>[0],
    "metadataSchema" | "dataSchemas" | "tools"
  >;

/** What `assistantMetadata` attaches to an answer. */
export interface AssistantMessageMetadata {
  readonly model?: string;
  /** When the answer started, as an ISO string. */
  readonly createdAt?: string;
  readonly finishReason?: FinishReason;
  readonly usage?: LanguageModelUsage;
}

/**
 * A `stream` option that sends the model and start time with the first chunk
 * and the finish reason and usage with the last, as message metadata.
 */
export function assistantMetadata<UI_MESSAGE extends UIMessage = UIMessage>(
  args: Pick<AssistantRunOptions<UI_MESSAGE>, "model">,
): AssistantStreamOptions<UI_MESSAGE> {
  const messageMetadata = ({
    part,
  }: {
    part: TextStreamPart<ToolSet>;
  }): AssistantMessageMetadata | undefined => {
    if (part.type === "start") {
      return { model: args.model, createdAt: new Date().toISOString() };
    }

    if (part.type === "finish") {
      return { finishReason: part.finishReason, usage: part.totalUsage };
    }

    return undefined;
  };

  // SAFETY: the app's metadata type is expected to accept AssistantMessageMetadata, as the docs say.
  return { messageMetadata } as AssistantStreamOptions<UI_MESSAGE>;
}

export interface AssistantOptions<UI_MESSAGE extends UIMessage = UIMessage> {
  /** Where the answer's stream is kept, so a reload resumes it. */
  readonly streams: StreamStore;
  /** Starts the generation: `agent.stream(...)` or `streamText(...)`. */
  readonly run: (
    args: AssistantRunOptions<UI_MESSAGE>,
  ) => AssistantRunResult | PromiseLike<AssistantRunResult>;
  /** The model when neither the request nor the chat names an allowed one. */
  readonly defaultModel: string;
  /**
   * The quota check before a generation (`usageQuota(usage, meter)`); an error
   * answers 429.
   */
  readonly quota?: (organizationId: string) => Promise<DbError | undefined>;
  /** Checks the user's message; `block` answers 403, others are recorded. */
  readonly moderate?: (input: {
    readonly message: AiMessage;
    readonly chat: AiChatRecord;
  }) => Promise<AssistantModeration | undefined>;
  /**
   * Called with the cost backfill payload when the gateway hasn't reported a
   * cost yet.
   */
  readonly enqueueCostBackfill?: (
    payload: CostBackfillPayload,
  ) => Promise<unknown>;
  /** Called after the answer is stored, such as to record usage. */
  readonly onFinish?: (
    finish: AssistantFinish<UI_MESSAGE>,
  ) => void | Promise<void>;
  /**
   * What the stream is kept for: seconds or a Postgres interval. Defaults to
   * one day.
   */
  readonly streamTtl?: number | string;
  /** The `feature` tag of the gateway options. Defaults to `chat`. */
  readonly feature?: string;
  /**
   * Turns a stream error into the message the client sees. Defaults to
   * `aiErrorMessage`, a fixed message per error kind.
   */
  readonly onError?: (error: unknown) => string;
  /**
   * What the client receives beside the text, such as `assistantMetadata` or
   * `sendReasoning: false`. A function gets the run's arguments.
   */
  readonly stream?:
    | AssistantStreamOptions<UI_MESSAGE>
    | ((
        args: AssistantRunOptions<UI_MESSAGE>,
      ) => AssistantStreamOptions<UI_MESSAGE>);
  /** Checks the user's message against schemas before it is stored. */
  readonly validate?: AssistantValidation<UI_MESSAGE>;
  /**
   * The secret the run signs tool approvals with
   * (`experimental_toolApprovalSecret` of `streamText` or the agent). The
   * assistant passes it to `run` and refuses an approval continuation whose
   * `signature` differs from the stored one; the AI SDK verifies the HMAC
   * itself when the history is replayed.
   */
  readonly toolApprovalSecret?: string | Uint8Array;
  /** Makes message and stream ids. Defaults to `crypto.randomUUID()`. */
  readonly generateId?: () => string;
  /**
   * Changes the answer before it is stored and passed to `onFinish`. The client
   * still receives the full stream. `collapseSpecParts` from
   * `better-supabase/json-render` folds streamed spec patches into one part.
   */
  readonly parts?: { readonly compact?: (message: UI_MESSAGE) => UI_MESSAGE };
}

/** The body `useAssistant` sends. */
export interface AssistantRequestBody<
  UI_MESSAGE extends UIMessage = UIMessage,
> {
  /** The chat id; the client may make it, and the chat is created on first use. */
  readonly id: string;
  /**
   * The user's message, or, to continue after a tool approval, the stored
   * assistant message with `approval-responded` parts. Only the decisions are
   * read from that one.
   */
  readonly message: UI_MESSAGE;
  readonly trigger?: AiUserMessageTrigger;
  /** For `regenerate-message`, the answer to write again. */
  readonly messageId?: string;
  readonly model?: string;
}

/** A checked and stored user turn, ready for a model: what `prepare` returns. */
export interface AssistantTurn<UI_MESSAGE extends UIMessage = UIMessage> {
  readonly chat: AiChatRecord;
  /** The model the request may use, after the catalog check. */
  readonly model: string;
  /** The stored user message, which the answer is saved under. */
  readonly parentId: string;
  /**
   * The assistant message this turn continues after a tool approval. The answer
   * is saved under the same id, so the approval and the output end up in one
   * message.
   */
  readonly continuationOf?: string;
  /** The history the model sees, as UI messages. */
  readonly uiMessages: UI_MESSAGE[];
  readonly messages: ModelMessage[];
  /** Spend attribution for the AI Gateway (`gatewayOptions`). */
  readonly providerOptions: { readonly gateway: GatewayOptions };
}

export interface Assistant<UI_MESSAGE extends UIMessage = UIMessage> {
  /** Stores the user's message, starts the answer and streams it (SSE). */
  respond(request: Request, context: AssistantContext): Promise<Response>;
  /**
   * The checks and writes before a generation, without one: parses the body
   * `useAssistant` sends, creates the chat on first use, picks the model,
   * moderates, checks the quota, stores the user's message and loads the
   * history. Returns a problem response when one of them fails.
   */
  prepare(
    body: unknown,
    context: AssistantContext,
  ): Promise<AssistantTurn<UI_MESSAGE> | Response>;
  /** The running answer of `chatId` from the start, or 204 when none runs. */
  resume(
    chatId: string,
    context: AssistantContext,
    options?: { readonly fromIdx?: number; readonly signal?: AbortSignal },
  ): Promise<Response>;
  /**
   * Asks the running answer to stop: 204 whether or not one runs, a problem
   * when the user may not.
   */
  stop(chatId: string, context: AssistantContext): Promise<Response>;
}

/** The chat's tenant as an optional `organizationId`, for a spread. */
export const tenantOf = (
  chat: Pick<AiChatRecord, "organizationId">,
): { readonly organizationId?: string } =>
  chat.organizationId === undefined
    ? {}
    : { organizationId: chat.organizationId };

const TRIGGERS: ReadonlySet<unknown> = new Set([
  "submit-message",
  "regenerate-message",
]);

/**
 * Whether the message answers a tool approval: an assistant message with a
 * decision.
 */
const respondsToApproval = (message: UIMessage): boolean =>
  message.role === "assistant" &&
  message.parts.some(
    (part) => isToolUIPart(part) && part.state === "approval-responded",
  );

function parseBody<UI_MESSAGE extends UIMessage>(
  value: unknown,
): AssistantRequestBody<UI_MESSAGE> | string {
  if (!isRecord(value)) {
    return "Expected a JSON object.";
  }

  const { id, trigger, messageId, model } = value;

  if (typeof id !== "string" || id === "") {
    return "Expected the chat id.";
  }

  const messages: unknown = value["messages"];
  const last: unknown = Array.isArray(messages) ? messages.at(-1) : undefined;
  const message = value["message"] ?? last;

  if (
    !isUIMessage(message) ||
    (message.role !== "user" && !respondsToApproval(message))
  ) {
    return "Expected the user's message or an approval decision.";
  }

  if (trigger !== undefined && !TRIGGERS.has(trigger)) {
    return "Expected submit-message or regenerate-message.";
  }

  return {
    id,
    // SAFETY: options.validate checks the message against the app's UI_MESSAGE schemas when set.
    message: message as UI_MESSAGE,
    ...(trigger === "regenerate-message" ? { trigger } : {}),
    ...(typeof messageId === "string" ? { messageId } : {}),
    ...(typeof model === "string" ? { model } : {}),
  };
}

/**
 * Copies the approval decisions of `sent` onto the stored assistant message
 * `stored`. Nothing else the client sent is used, so a forged output or input
 * changes nothing. With a `secret`, a decision must carry the signature the
 * stored request has.
 */
function decide(
  stored: UIMessage,
  sent: UIMessage,
  secret: string | Uint8Array | undefined,
): UIMessage | DbError {
  const decisions = sent.parts.filter(isToolUIPart);
  const outcome = { applied: 0, forged: false };

  const parts = stored.parts.map((part) => {
    if (!isToolUIPart(part) || part.approval === undefined) {
      return part;
    }

    const { approval } = part;

    const match = decisions.find(
      (candidate) =>
        candidate.toolCallId === part.toolCallId &&
        candidate.state === "approval-responded" &&
        candidate.approval.id === approval.id,
    );

    if (match?.state !== "approval-responded") {
      return part;
    }

    if (
      secret !== undefined &&
      match.approval.signature !== approval.signature
    ) {
      outcome.forged = true;

      return part;
    }

    if (part.state !== "approval-requested") {
      return part;
    }

    outcome.applied += 1;

    // SAFETY: only the decision and its reason change; the part keeps its tool, input and signature.
    return {
      ...part,
      state: "approval-responded" as const,
      approval: {
        ...approval,
        approved: match.approval.approved,
        ...(match.approval.reason === undefined
          ? {}
          : { reason: match.approval.reason }),
      },
    };
  });

  if (outcome.forged) {
    return dbError("forbidden", "The approval does not match its request.", {
      code: "AI_APPROVAL_SIGNATURE",
    });
  }

  return outcome.applied === 0
    ? dbError("conflict", "No pending approval matches the decision.", {
        code: "AI_APPROVAL_NOT_PENDING",
      })
    : { ...stored, parts };
}

const settle = async <T>(
  value: PromiseLike<T> | undefined,
): Promise<T | undefined> => {
  try {
    return await value;
  } catch {
    return undefined;
  }
};

const uiChunksOf = <UI_MESSAGE extends UIMessage>(
  result: AssistantRunResult,
  options: UIStreamOptions<UI_MESSAGE>,
): ReadableStream<UIMessageChunk> | undefined =>
  result.stream === undefined
    ? undefined
    : toUIMessageStream({
        stream: result.stream,
        ...(result.tools === undefined ? {} : { tools: result.tools }),
        ...options,
      });

/**
 * A chat route for the AI SDK on the `ai-chat` block: `respond` stores the
 * user's message, picks an allowed model, checks the quota, claims the chat's
 * answer, runs the model and streams it while keeping a copy in the stream
 * store; the answer and its usage are stored when it ends, even after the
 * client left. `resume` replays it after a reload, `stop` ends it.
 */
export function createAssistant<UI_MESSAGE extends UIMessage = UIMessage>(
  options: AssistantOptions<UI_MESSAGE>,
): Assistant<UI_MESSAGE> {
  const newId = options.generateId ?? (() => crypto.randomUUID());

  async function chatOf(
    context: AssistantContext,
    body: AssistantRequestBody<UI_MESSAGE>,
  ): Promise<AiChatRecord | Response> {
    const found = await context.chats.chats.get(body.id);

    if (found.ok) {
      return found.data;
    }

    if (found.error.kind !== "not_found") {
      return problemResponse(found.error);
    }

    const created = await context.chats.chats.create({
      organizationId: context.organizationId,
      input: {
        id: body.id,
        ...(body.model === undefined ? {} : { model: body.model }),
      },
    });

    return created.ok ? created.data : problemResponse(created.error);
  }

  async function modelOf(
    context: AssistantContext,
    chat: AiChatRecord,
    requested: string | undefined,
  ): Promise<string | Response> {
    const allowed = await context.chats.models.allowed(chat.organizationId);

    if (!allowed.ok) {
      return problemResponse(allowed.error);
    }

    const ids = new Set(allowed.data.map((model) => model.id));
    const fits = (id: string) => ids.size === 0 || ids.has(id);

    if (requested !== undefined && fits(requested)) {
      return requested;
    }

    if (requested !== undefined) {
      return problemResponse(
        dbError("forbidden", `The model ${requested} is not allowed.`, {
          code: "AI_MODEL_NOT_ALLOWED",
        }),
      );
    }

    if (chat.model !== undefined && fits(chat.model)) {
      return chat.model;
    }

    if (fits(options.defaultModel)) {
      return options.defaultModel;
    }

    const first = allowed.data[0];

    return first === undefined ? options.defaultModel : first.id;
  }

  async function moderated(
    context: AssistantContext,
    chat: AiChatRecord,
    message: AiMessage,
  ): Promise<Response | undefined> {
    const verdict = await options.moderate?.({ message, chat });

    if (verdict === undefined || verdict.action === "allow") {
      return undefined;
    }

    await context.chats.moderation.record({
      event: {
        ...tenantOf(chat),
        chatId: chat.id,
        messageId: message.id,
        userId: context.userId,
        stage: "input",
        action: verdict.action,
        category: verdict.category,
        ...(verdict.score === undefined ? {} : { score: verdict.score }),
      },
    });

    return verdict.action === "block"
      ? problemResponse(
          dbError("forbidden", "The message was blocked.", {
            code: "AI_MODERATION_BLOCKED",
          }),
        )
      : undefined;
  }

  const historyOf = (path: readonly AiStoredMessage[]): UI_MESSAGE[] => {
    const repaired = new Map(
      repairDanglingToolCalls(pathToHistory(path)).map((message) => [
        message.id,
        message,
      ]),
    );

    return toUIMessages<UI_MESSAGE>(
      path.map((stored) =>
        stored.format === AI_SDK_UI_FORMAT || stored.format === "native"
          ? stored
          : (repaired.get(stored.id) ?? stored),
      ),
    );
  };

  async function turnOf(
    context: AssistantContext,
    chat: AiChatRecord,
    model: string,
    parentId: string,
    uiMessages: UI_MESSAGE[],
    continuationOf?: string,
  ): Promise<AssistantTurn<UI_MESSAGE>> {
    return {
      chat,
      model,
      parentId,
      ...(continuationOf === undefined ? {} : { continuationOf }),
      uiMessages,
      messages: await convertToModelMessages(uiMessages, {
        ignoreIncompleteToolCalls: true,
      }),
      providerOptions: gatewayOptions({
        userId: context.userId,
        ...tenantOf(chat),
        chatId: chat.id,
        feature: options.feature ?? "chat",
      }),
    };
  }

  /**
   * Continues the stored assistant message `body.message` after a tool
   * approval.
   */
  async function approved(
    body: AssistantRequestBody<UI_MESSAGE>,
    context: AssistantContext,
  ): Promise<AssistantTurn<UI_MESSAGE> | Response> {
    const found = await context.chats.chats.get(body.id);

    if (!found.ok) {
      return problemResponse(found.error);
    }

    const chat = found.data;
    const model = await modelOf(context, chat, body.model);

    if (model instanceof Response) {
      return model;
    }

    if (options.quota && chat.organizationId !== undefined) {
      const exceeded = await options.quota(chat.organizationId);

      if (exceeded) {
        return problem429(exceeded);
      }
    }

    const path = await context.chats.messages.path({
      chatId: chat.id,
      leafId: body.message.id,
      native: true,
    });

    if (!path.ok) {
      return problemResponse(path.error);
    }

    const stored = path.data.at(-1);

    if (
      stored?.id !== body.message.id ||
      stored.role !== "assistant" ||
      stored.parentId === undefined
    ) {
      return badRequest("The message to continue is not a stored answer.");
    }

    const decided = decide(
      toUIMessage(stored),
      body.message,
      options.toolApprovalSecret,
    );

    if ("kind" in decided) {
      return problemResponse(decided);
    }

    return turnOf(
      context,
      chat,
      model,
      stored.parentId,
      // SAFETY: a stored message is the app's UI_MESSAGE; decide only changed approval states.
      [...historyOf(path.data.slice(0, -1)), decided as UI_MESSAGE],
      stored.id,
    );
  }

  async function prepare(
    value: unknown,
    context: AssistantContext,
  ): Promise<AssistantTurn<UI_MESSAGE> | Response> {
    const body = parseBody<UI_MESSAGE>(value);

    if (typeof body === "string") {
      return badRequest(body);
    }

    if (options.validate !== undefined) {
      const checked = await safeValidateUIMessages<UI_MESSAGE>({
        messages: [body.message],
        ...options.validate,
      });

      if (!checked.success) {
        return problemResponse(
          dbError("validation", "The message did not match its schema.", {
            code: "AI_MESSAGE_INVALID",
            issues: [{ message: checked.error.message }],
          }),
        );
      }
    }

    if (body.message.role === "assistant") {
      return approved(body, context);
    }

    const chat = await chatOf(context, body);

    if (chat instanceof Response) {
      return chat;
    }

    const model = await modelOf(context, chat, body.model);

    if (model instanceof Response) {
      return model;
    }

    const userMessage = fromUIMessage(body.message);
    const blocked = await moderated(context, chat, userMessage);

    if (blocked) {
      return blocked;
    }

    if (options.quota && chat.organizationId !== undefined) {
      const exceeded = await options.quota(chat.organizationId);

      if (exceeded) {
        return problem429(exceeded);
      }
    }

    const appended = await context.chats.messages.appendUser({
      chatId: chat.id,
      message: userMessage,
      ...(body.trigger === undefined ? {} : { trigger: body.trigger }),
      ...(body.messageId === undefined ? {} : { messageId: body.messageId }),
      native: body.message,
    });

    if (!appended.ok) {
      return problemResponse(appended.error);
    }

    const parentId = appended.data.messageId;

    const path = await context.chats.messages.path({
      chatId: chat.id,
      leafId: parentId,
      native: true,
    });

    if (!path.ok) {
      return problemResponse(path.error);
    }

    return turnOf(context, chat, model, parentId, historyOf(path.data));
  }

  async function respond(
    request: Request,
    context: AssistantContext,
  ): Promise<Response> {
    const turn = await prepare(await readJson(request), context);

    if (turn instanceof Response) {
      return turn;
    }

    const { chat, model, parentId, uiMessages } = turn;

    const streamId = newId();
    const assistantId = turn.continuationOf ?? newId();

    const claim = await context.chats.runs.claim({
      chatId: chat.id,
      streamId,
      model,
      messageId: assistantId,
    });

    if (!claim.ok) {
      return problemResponse(claim.error);
    }

    if (!claim.data.claimed) {
      return problemResponse(
        dbError("conflict", "An answer is already being written.", {
          code: "AI_CHAT_BUSY",
        }),
      );
    }

    const runId = claim.data.runId;
    const abort = new AbortController();

    const release = (status: AiRunStatus, usage?: AiUsage, error?: string) =>
      context.chats.runs.release({
        chatId: chat.id,
        streamId,
        ...runRelease(status, usage, error),
      });

    const runArgs: AssistantRunOptions<UI_MESSAGE> = {
      chat,
      model,
      messages: turn.messages,
      uiMessages,
      abortSignal: abort.signal,
      providerOptions: turn.providerOptions,
      ...(options.toolApprovalSecret === undefined
        ? {}
        : { toolApprovalSecret: options.toolApprovalSecret }),
      ...(turn.continuationOf === undefined
        ? {}
        : { continuationOf: turn.continuationOf }),
      context,
    };

    let result: AssistantRunResult;

    try {
      result = await options.run(runArgs);
    } catch (cause) {
      await release("failed", undefined, String(cause));

      const mapped = aiErrorToDbError(cause);

      return problemResponse(
        mapped.kind === "unexpected"
          ? dbError("unexpected", "The answer could not be started.", {
              code: "AI_CHAT_RUN_FAILED",
            })
          : mapped,
      );
    }

    let finished: Promise<void> | undefined;

    const onEnd: UIMessageStreamOnEndCallback<UI_MESSAGE> = (event) => {
      const responseMessage =
        options.parts?.compact?.(event.responseMessage) ??
        event.responseMessage;

      finished = (async () => {
        const stopped = event.isAborted || abort.signal.aborted;
        const status: AiRunStatus = stopped ? "cancelled" : "completed";

        const saved = await context.chats.messages.saveAssistant({
          chatId: chat.id,
          message: fromUIMessage(responseMessage),
          options: {
            parentId,
            status: stopped ? "aborted" : "complete",
            model,
            format: AI_SDK_UI_FORMAT,
            native: responseMessage,
            runId,
          },
        });

        const usage = usageOf({
          usage: await settle(result.usage),
          finalStep: await settle(result.finalStep),
        });

        await release(
          saved.ok ? status : "failed",
          usage,
          saved.ok ? undefined : saved.error.message,
        );

        if (
          usage.costMicroUsd === undefined &&
          usage.generationId !== undefined &&
          options.enqueueCostBackfill
        ) {
          await options.enqueueCostBackfill({
            generationId: usage.generationId,
            ...tenantOf(chat),
          });
        }

        await options.onFinish?.({
          chat,
          message: responseMessage,
          status,
          model,
          usage,
          context,
        });
      })();

      return finished;
    };

    const extra =
      typeof options.stream === "function"
        ? options.stream(runArgs)
        : (options.stream ?? {});

    const streamOptions = {
      ...extra,
      originalMessages: uiMessages,
      generateMessageId: () => assistantId,
      onEnd,
      onError: options.onError ?? aiErrorMessage,
    };

    const chunks = uiChunksOf(result, streamOptions);

    if (chunks === undefined) {
      await release("failed", undefined, "The run returned no stream.");

      return problemResponse(
        dbError("unexpected", "The answer could not be started.", {
          code: "AI_CHAT_RUN_FAILED",
        }),
      );
    }

    const teed = teeToStore(
      options.streams,
      streamId,
      chunks.pipeThrough(new JsonToSseTransformStream()),
      {
        owner: chat.ownerId,
        ...(chat.organizationId === undefined
          ? {}
          : { tenant: chat.organizationId }),
        kind: "chat",
        ...(options.streamTtl === undefined ? {} : { ttl: options.streamTtl }),
        onCancel: () => {
          abort.abort();
        },
      },
    );

    context.waitUntil?.(
      (async () => {
        await teed.persisted;
        await finished;
      })(),
    );

    return sse(teed.stream);
  }

  async function resume(
    chatId: string,
    context: AssistantContext,
    resumeOptions: {
      readonly fromIdx?: number;
      readonly signal?: AbortSignal;
    } = {},
  ): Promise<Response> {
    const chat = await context.chats.chats.get(chatId);

    if (!chat.ok) {
      return chat.error.kind === "not_found"
        ? new Response(null, { status: 204 })
        : problemResponse(chat.error);
    }

    const { activeStreamId } = chat.data;

    if (activeStreamId === undefined) {
      return new Response(null, { status: 204 });
    }

    const stream = await resumeFromStore(options.streams, activeStreamId, {
      ...(resumeOptions.fromIdx === undefined
        ? {}
        : { fromIdx: resumeOptions.fromIdx }),
      ...(resumeOptions.signal === undefined
        ? {}
        : { signal: resumeOptions.signal }),
    });

    if (!stream.ok) {
      return problemResponse(stream.error);
    }

    return stream.data === undefined
      ? new Response(null, { status: 204 })
      : sse(stream.data);
  }

  async function stop(
    chatId: string,
    context: AssistantContext,
  ): Promise<Response> {
    const stopped = await context.chats.runs.stop(chatId);

    if (!stopped.ok) {
      return problemResponse(stopped.error);
    }

    return new Response(null, { status: 204 });
  }

  return { respond, prepare, resume, stop };
}
