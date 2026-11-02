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

/** The options the deprecated `toUIMessageStream()` method gets. */
interface LegacyUIMessageStreamOptions extends AssistantStreamOptions {
  originalMessages: UIMessage[];
  generateMessageId: () => string;
  onEnd: UIMessageStreamOnEndCallback<UIMessage>;
  onError?: (error: unknown) => string;
}

/**
 * The part of a `streamText` or `agent.stream` result the assistant reads. A
 * result of `streamText({ experimental_lowMemory: true })` fits too; it has no
 * `finalStep`, so the gateway's cost and generation id stay unknown.
 */
export interface AssistantRunResult {
  /** The full stream; the assistant turns it into UI message chunks. */
  readonly stream?: ReadableStream<TextStreamPart<ToolSet>>;
  /** The usage of every step together. */
  readonly usage?: PromiseLike<LanguageModelUsage>;
  /** The last step, whose `providerMetadata` carries the gateway's cost. */
  readonly finalStep?: PromiseLike<{ readonly providerMetadata?: unknown }>;
  /**
   * @deprecated Return a result with `stream`. Read only when `stream` is
   * missing; removed in 0.33.
   */
  toUIMessageStream?(
    options: LegacyUIMessageStreamOptions,
  ): ReadableStream<UIMessageChunk>;
  /** @deprecated Return `usage`; removed in 0.33. */
  readonly totalUsage?: PromiseLike<LanguageModelUsage>;
  /** @deprecated Return `finalStep`; removed in 0.33. */
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

/**
 * The `toUIMessageStream` options an app may set: what the client receives
 * beside the text. `originalMessages`, `generateMessageId` and the end
 * callbacks stay with the assistant, which stores the answer.
 */
export type AssistantStreamOptions = Pick<
  UIMessageStreamOptions<UIMessage>,
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
export type AssistantValidation = Pick<
  Parameters<typeof safeValidateUIMessages<UIMessage>>[0],
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
export function assistantMetadata(
  args: Pick<AssistantRunArgs, "model">,
): AssistantStreamOptions {
  return {
    messageMetadata: ({ part }): AssistantMessageMetadata | undefined => {
      if (part.type === "start") {
        return { model: args.model, createdAt: new Date().toISOString() };
      }

      if (part.type === "finish") {
        return { finishReason: part.finishReason, usage: part.totalUsage };
      }

      return undefined;
    },
  };
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
  readonly onFinish?: (finish: AssistantFinish) => void | Promise<void>;
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
    | AssistantStreamOptions
    | ((args: AssistantRunArgs) => AssistantStreamOptions);
  /** Checks the user's message against schemas before it is stored. */
  readonly validate?: AssistantValidation;
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
   * The checks and writes before a generation, without one: parses the body
   * `useAssistant` sends, creates the chat on first use, picks the model,
   * moderates, checks the quota, stores the user's message and loads the
   * history. Returns a problem response when one of them fails.
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

function parseBody(value: unknown): AssistantRequestBody | string {
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

  if (!isUIMessage(message) || message.role !== "user") {
    return "Expected the user's message.";
  }

  if (trigger !== undefined && !TRIGGERS.has(trigger)) {
    return "Expected submit-message or regenerate-message.";
  }

  return {
    id,
    message,
    ...(trigger === "regenerate-message" ? { trigger } : {}),
    ...(typeof messageId === "string" ? { messageId } : {}),
    ...(typeof model === "string" ? { model } : {}),
  };
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

const uiChunksOf = (
  result: AssistantRunResult,
  options: LegacyUIMessageStreamOptions,
): ReadableStream<UIMessageChunk> | undefined => {
  if (result.stream !== undefined) {
    return toUIMessageStream({ stream: result.stream, ...options });
  }

  // oxlint-disable-next-line typescript/no-deprecated -- read for 0.32 results that predate `stream`.
  return result.toUIMessageStream?.(options);
};

/**
 * A chat route for the AI SDK on the `ai-chat` block: `respond` stores the
 * user's message, picks an allowed model, checks the quota, claims the chat's
 * answer, runs the model and streams it while keeping a copy in the stream
 * store; the answer and its usage are stored when it ends, even after the
 * client left. `resume` replays it after a reload, `stop` ends it.
 */
export function createAssistant(options: AssistantOptions): Assistant {
  const newId = options.generateId ?? (() => crypto.randomUUID());

  async function chatOf(
    context: AssistantContext,
    body: AssistantRequestBody,
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

  async function prepare(
    value: unknown,
    context: AssistantContext,
  ): Promise<AssistantTurn | Response> {
    const body = parseBody(value);

    if (typeof body === "string") {
      return badRequest(body);
    }

    if (options.validate !== undefined) {
      const checked = await safeValidateUIMessages({
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

    const repaired = new Map(
      repairDanglingToolCalls(pathToHistory(path.data)).map((message) => [
        message.id,
        message,
      ]),
    );

    const uiMessages = toUIMessages(
      path.data.map((stored) =>
        stored.format === AI_SDK_UI_FORMAT || stored.format === "native"
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
        ...tenantOf(chat),
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

    if (turn instanceof Response) {
      return turn;
    }

    const { chat, model, parentId, uiMessages } = turn;

    const streamId = newId();
    const assistantId = newId();

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

    const runArgs: AssistantRunArgs = {
      chat,
      model,
      messages: turn.messages,
      uiMessages,
      abortSignal: abort.signal,
      providerOptions: turn.providerOptions,
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

    const onEnd: UIMessageStreamOnEndCallback<UIMessage> = (event) => {
      finished = (async () => {
        const stopped = event.isAborted || abort.signal.aborted;
        const status: AiRunStatus = stopped ? "cancelled" : "completed";

        const saved = await context.chats.messages.saveAssistant({
          chatId: chat.id,
          message: fromUIMessage(event.responseMessage),
          options: {
            parentId,
            status: stopped ? "aborted" : "complete",
            model,
            format: AI_SDK_UI_FORMAT,
            native: event.responseMessage,
            runId,
          },
        });

        const usage = usageOf({
          // oxlint-disable-next-line typescript/no-deprecated -- read for 0.32 results that predate `usage`.
          usage: await settle(result.usage ?? result.totalUsage),
          finalStep:
            result.finalStep === undefined
              ? // oxlint-disable-next-line typescript/no-deprecated -- read for 0.32 results that predate `finalStep`.
                { providerMetadata: await settle(result.providerMetadata) }
              : await settle(result.finalStep),
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
          message: event.responseMessage,
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
