import {
  convertToModelMessages,
  JsonToSseTransformStream,
  type LanguageModelUsage,
  type ModelMessage,
  UI_MESSAGE_STREAM_HEADERS,
  type UIMessage,
  type UIMessageChunk,
  type UIMessageStreamOnEndCallback,
} from "ai";

import type {
  AiChat,
  AiChatRecord,
  AiModerationAction,
  AiRunStatus,
  AiUserMessageTrigger,
} from "../../blocks/ai-chat/ai-chat.ts";
import type { AiMessage } from "../../blocks/ai-chat/message.ts";
import type { DbError } from "../../core/errors.ts";
import type { StreamStore } from "../../streams/store.ts";

import {
  pathToHistory,
  repairDanglingToolCalls,
} from "../../blocks/ai-chat/history.ts";
import { isRecord } from "../../blocks/shared.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { resumeFromStore, teeToStore } from "../../streams/tee.ts";
import {
  type AiUsage,
  type CostBackfillPayload,
  gatewayOptions,
  type GatewayOptions,
  problem429,
  runRelease,
  usageOf,
} from "../gateway.ts";
import {
  AI_SDK_UI_FORMAT,
  fromUIMessage,
  isUIMessage,
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
  readonly organizationId: string;
  /**
   * Keeps the function alive until the answer is stored, after the response
   * is sent: `after` in Next.js, `ctx.waitUntil` on Workers and Vercel.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/** What `run` gets to generate one answer. */
export interface AssistantRunArgs {
  readonly chat: AiChatRecord;
  /** The model the request may use, after the catalog check. */
  readonly model: string;
  readonly messages: ModelMessage[];
  /** The history the model sees, as UI messages. */
  readonly uiMessages: UIMessage[];
  /** Aborted by `stop()`; pass it to `streamText` or `agent.stream`. */
  readonly abortSignal: AbortSignal;
  /** Spend attribution for the AI Gateway (`gatewayOptions`). */
  readonly providerOptions: { readonly gateway: GatewayOptions };
  readonly context: AssistantContext;
}

/** The part of a `streamText` or `agent.stream` result the assistant reads. */
export interface AssistantRunResult {
  toUIMessageStream(options: {
    originalMessages: UIMessage[];
    generateMessageId: () => string;
    onEnd: UIMessageStreamOnEndCallback<UIMessage>;
    onError?: (error: unknown) => string;
  }): ReadableStream<UIMessageChunk>;
  readonly totalUsage?: PromiseLike<LanguageModelUsage>;
  readonly providerMetadata?: PromiseLike<unknown>;
}

/** The verdict of a moderation hook. */
export interface AssistantModeration {
  readonly action: AiModerationAction;
  readonly category: string;
  readonly score?: number;
}

/** What `onFinish` gets once the answer is stored. */
export interface AssistantFinish {
  readonly chat: AiChatRecord;
  readonly message: UIMessage;
  readonly status: AiRunStatus;
  readonly model: string;
  readonly usage: AiUsage | undefined;
  readonly context: AssistantContext;
}

export interface AssistantOptions {
  /** Where the answer's stream is kept, so a reload resumes it. */
  readonly streams: StreamStore;
  /** Starts the generation: `agent.stream(...)` or `streamText(...)`. */
  readonly run: (
    args: AssistantRunArgs,
  ) => AssistantRunResult | PromiseLike<AssistantRunResult>;
  /** The model when neither the request nor the chat names an allowed one. */
  readonly defaultModel: string;
  /**
   * The quota check before a generation (`usageQuota(usage, meter)`); an
   * error answers 429.
   */
  readonly quota?: (organizationId: string) => Promise<DbError | undefined>;
  /** Checks the user's message; `block` answers 403, others are recorded. */
  readonly moderate?: (input: {
    readonly message: AiMessage;
    readonly chat: AiChatRecord;
  }) => Promise<AssistantModeration | undefined>;
  /** Called with the cost backfill payload when the gateway hasn't reported a cost yet. */
  readonly enqueueCostBackfill?: (
    payload: CostBackfillPayload,
  ) => Promise<unknown>;
  /** Called after the answer is stored, such as to record usage. */
  readonly onFinish?: (finish: AssistantFinish) => void | Promise<void>;
  /** What the stream is kept for: seconds or a Postgres interval. Defaults to one day. */
  readonly streamTtl?: number | string;
  /** The `feature` tag of the gateway options. Defaults to `chat`. */
  readonly feature?: string;
  /** Turns a stream error into the message the client sees. */
  readonly onError?: (error: unknown) => string;
  /** Makes message and stream ids. Defaults to `crypto.randomUUID()`. */
  readonly generateId?: () => string;
}

/** The body `useAssistant` sends. */
export interface AssistantRequestBody {
  /** The chat id; the client may make it, and the chat is created on first use. */
  readonly id: string;
  readonly message: UIMessage;
  readonly trigger?: AiUserMessageTrigger;
  /** For `regenerate-message`, the answer to write again. */
  readonly messageId?: string;
  readonly model?: string;
}

/** A checked and stored user turn, ready for a model: what `prepare` returns. */
export interface AssistantTurn {
  readonly chat: AiChatRecord;
  /** The model the request may use, after the catalog check. */
  readonly model: string;
  /** The stored user message, which the answer is saved under. */
  readonly parentId: string;
  /** The history the model sees, as UI messages. */
  readonly uiMessages: UIMessage[];
  readonly messages: ModelMessage[];
  /** Spend attribution for the AI Gateway (`gatewayOptions`). */
  readonly providerOptions: { readonly gateway: GatewayOptions };
}

export interface Assistant {
  /** Stores the user's message, starts the answer and streams it (SSE). */
  respond(request: Request, context: AssistantContext): Promise<Response>;
  /**
   * The checks and writes before a generation, without one: parses the
   * body `useAssistant` sends, creates the chat on first use, picks the
   * model, moderates, checks the quota, stores the user's message and loads
   * the history. Returns a problem response when one of them fails.
   */
  prepare(
    body: unknown,
    context: AssistantContext,
  ): Promise<AssistantTurn | Response>;
  /** The running answer of `chatId` from the start, or 204 when none runs. */
  resume(
    chatId: string,
    context: AssistantContext,
    options?: { readonly fromIdx?: number; readonly signal?: AbortSignal },
  ): Promise<Response>;
  /** Asks the running answer to stop: 204 whether or not one runs, a problem when the user may not. */
  stop(chatId: string, context: AssistantContext): Promise<Response>;
}

const TRIGGERS: ReadonlySet<unknown> = new Set([
  "submit-message",
  "regenerate-message",
]);

function badRequest(message: string): Response {
  return problemResponse(
    dbError("invalid_request", message, { code: "AI_CHAT_BAD_REQUEST" }),
  );
}

function parseBody(value: unknown): AssistantRequestBody | string {
  if (!isRecord(value)) return "Expected a JSON object.";
  const { id, trigger, messageId, model } = value;
  if (typeof id !== "string" || id === "") return "Expected the chat id.";
  const messages: unknown = value["messages"];
  const last: unknown = Array.isArray(messages) ? messages.at(-1) : undefined;
  const message = value["message"] ?? last;
  if (!isUIMessage(message) || message.role !== "user")
    return "Expected the user's message.";
  if (trigger !== undefined && !TRIGGERS.has(trigger))
    return "Expected submit-message or regenerate-message.";
  return {
    id,
    message,
    ...(trigger === "regenerate-message" ? { trigger } : {}),
    ...(typeof messageId === "string" ? { messageId } : {}),
    ...(typeof model === "string" ? { model } : {}),
  };
}

async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return undefined;
  }
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

function sse(stream: ReadableStream<string>): Response {
  return new Response(stream.pipeThrough(new TextEncoderStream()), {
    headers: UI_MESSAGE_STREAM_HEADERS,
  });
}

/**
 * A chat route for the AI SDK on the `ai-chat` block: `respond` stores the
 * user's message, picks an allowed model, checks the quota, claims the
 * chat's answer, runs the model and streams it while keeping a copy in the
 * stream store; the answer and its usage are stored when it ends, even
 * after the client left. `resume` replays it after a reload, `stop` ends it.
 */
export function createAssistant(options: AssistantOptions): Assistant {
  const newId = options.generateId ?? (() => crypto.randomUUID());

  async function chatOf(
    context: AssistantContext,
    body: AssistantRequestBody,
  ): Promise<AiChatRecord | Response> {
    const found = await context.chats.chats.get(body.id);
    if (found.ok) return found.data;
    if (found.error.kind !== "not_found") return problemResponse(found.error);
    const created = await context.chats.chats.create(context.organizationId, {
      id: body.id,
      ...(body.model === undefined ? {} : { model: body.model }),
    });
    return created.ok ? created.data : problemResponse(created.error);
  }

  async function modelOf(
    context: AssistantContext,
    chat: AiChatRecord,
    requested: string | undefined,
  ): Promise<string | Response> {
    const allowed = await context.chats.models.allowed(chat.organizationId);
    if (!allowed.ok) return problemResponse(allowed.error);
    const ids = new Set(allowed.data.map((model) => model.id));
    const fits = (id: string) => ids.size === 0 || ids.has(id);
    if (requested !== undefined && fits(requested)) return requested;
    if (requested !== undefined)
      return problemResponse(
        dbError("forbidden", `The model ${requested} is not allowed.`, {
          code: "AI_MODEL_NOT_ALLOWED",
        }),
      );
    if (chat.model !== undefined && fits(chat.model)) return chat.model;
    if (fits(options.defaultModel)) return options.defaultModel;
    const first = allowed.data[0];
    return first === undefined ? options.defaultModel : first.id;
  }

  async function moderated(
    context: AssistantContext,
    chat: AiChatRecord,
    message: AiMessage,
  ): Promise<Response | undefined> {
    const verdict = await options.moderate?.({ message, chat });
    if (verdict === undefined || verdict.action === "allow") return undefined;
    await context.chats.moderation.record({
      organizationId: chat.organizationId,
      chatId: chat.id,
      messageId: message.id,
      userId: context.userId,
      stage: "input",
      action: verdict.action,
      category: verdict.category,
      ...(verdict.score === undefined ? {} : { score: verdict.score }),
    });
    return verdict.action === "block"
      ? problemResponse(
          dbError("forbidden", "The message was blocked.", {
            code: "AI_MODERATION_BLOCKED",
          }),
        )
      : undefined;
  }

  async function prepare(
    value: unknown,
    context: AssistantContext,
  ): Promise<AssistantTurn | Response> {
    const body = parseBody(value);
    if (typeof body === "string") return badRequest(body);
    const chat = await chatOf(context, body);
    if (chat instanceof Response) return chat;
    const model = await modelOf(context, chat, body.model);
    if (model instanceof Response) return model;
    const userMessage = fromUIMessage(body.message);
    const blocked = await moderated(context, chat, userMessage);
    if (blocked) return blocked;
    if (options.quota) {
      const exceeded = await options.quota(chat.organizationId);
      if (exceeded) return problem429(exceeded);
    }
    const appended = await context.chats.messages.appendUser(
      chat.id,
      userMessage,
      {
        ...(body.trigger === undefined ? {} : { trigger: body.trigger }),
        ...(body.messageId === undefined ? {} : { messageId: body.messageId }),
      },
    );
    if (!appended.ok) return problemResponse(appended.error);
    const parentId = appended.data.messageId;
    const path = await context.chats.messages.path(chat.id, {
      leafId: parentId,
      native: true,
    });
    if (!path.ok) return problemResponse(path.error);
    const repaired = new Map(
      repairDanglingToolCalls(pathToHistory(path.data)).map((message) => [
        message.id,
        message,
      ]),
    );
    const uiMessages = toUIMessages(
      path.data.map((stored) =>
        stored.format === AI_SDK_UI_FORMAT
          ? stored
          : (repaired.get(stored.id) ?? stored),
      ),
    );
    return {
      chat,
      model,
      parentId,
      uiMessages,
      messages: await convertToModelMessages(uiMessages, {
        ignoreIncompleteToolCalls: true,
      }),
      providerOptions: gatewayOptions({
        userId: context.userId,
        organizationId: chat.organizationId,
        chatId: chat.id,
        feature: options.feature ?? "chat",
      }),
    };
  }

  async function respond(
    request: Request,
    context: AssistantContext,
  ): Promise<Response> {
    const turn = await prepare(await readJson(request), context);
    if (turn instanceof Response) return turn;
    const { chat, model, parentId, uiMessages } = turn;

    const streamId = newId();
    const assistantId = newId();
    const claim = await context.chats.runs.claim(chat.id, streamId, {
      model,
      messageId: assistantId,
    });
    if (!claim.ok) return problemResponse(claim.error);
    if (!claim.data.claimed)
      return problemResponse(
        dbError("conflict", "An answer is already being written.", {
          code: "AI_CHAT_BUSY",
        }),
      );
    const runId = claim.data.runId;
    const abort = new AbortController();
    const release = (status: AiRunStatus, usage?: AiUsage, error?: string) =>
      context.chats.runs.release(
        chat.id,
        streamId,
        runRelease(status, usage, error),
      );

    let result: AssistantRunResult;
    try {
      result = await options.run({
        chat,
        model,
        messages: turn.messages,
        uiMessages,
        abortSignal: abort.signal,
        providerOptions: turn.providerOptions,
        context,
      });
    } catch (cause) {
      await release("error", undefined, String(cause));
      return problemResponse(
        dbError("unexpected", "The answer could not be started.", {
          code: "AI_CHAT_RUN_FAILED",
        }),
      );
    }

    let finished: Promise<void> | undefined;
    const onEnd: UIMessageStreamOnEndCallback<UIMessage> = (event) => {
      finished = (async () => {
        const stopped = event.isAborted || abort.signal.aborted;
        const status: AiRunStatus = stopped ? "stopped" : "done";
        const saved = await context.chats.messages.saveAssistant(
          chat.id,
          fromUIMessage(event.responseMessage),
          {
            parentId,
            status: stopped ? "aborted" : "complete",
            model,
            format: AI_SDK_UI_FORMAT,
            native: event.responseMessage,
            runId,
          },
        );
        const usage = usageOf({
          totalUsage: await settle(result.totalUsage),
          providerMetadata: await settle(result.providerMetadata),
        });
        await release(
          saved.ok ? status : "error",
          usage,
          saved.ok ? undefined : saved.error.message,
        );
        if (
          usage.costMicroUsd === undefined &&
          usage.generationId !== undefined &&
          options.enqueueCostBackfill
        )
          await options.enqueueCostBackfill({
            generationId: usage.generationId,
            organizationId: chat.organizationId,
          });
        await options.onFinish?.({
          chat,
          message: event.responseMessage,
          status,
          model,
          usage,
          context,
        });
      })();
      return finished;
    };

    const chunks = result.toUIMessageStream({
      originalMessages: uiMessages,
      generateMessageId: () => assistantId,
      onEnd,
      ...(options.onError === undefined ? {} : { onError: options.onError }),
    });
    const teed = teeToStore(
      options.streams,
      streamId,
      chunks.pipeThrough(new JsonToSseTransformStream()),
      {
        owner: chat.ownerId,
        tenant: chat.organizationId,
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
    if (!chat.ok)
      return chat.error.kind === "not_found"
        ? new Response(null, { status: 204 })
        : problemResponse(chat.error);
    const { activeStreamId } = chat.data;
    if (activeStreamId === undefined)
      return new Response(null, { status: 204 });
    const stream = await resumeFromStore(options.streams, activeStreamId, {
      ...(resumeOptions.fromIdx === undefined
        ? {}
        : { fromIdx: resumeOptions.fromIdx }),
      ...(resumeOptions.signal === undefined
        ? {}
        : { signal: resumeOptions.signal }),
    });
    if (!stream.ok) return problemResponse(stream.error);
    return stream.data === undefined
      ? new Response(null, { status: 204 })
      : sse(stream.data);
  }

  async function stop(
    chatId: string,
    context: AssistantContext,
  ): Promise<Response> {
    const stopped = await context.chats.runs.stop(chatId);
    if (!stopped.ok) return problemResponse(stopped.error);
    return new Response(null, { status: 204 });
  }

  return { respond, prepare, resume, stop };
}
