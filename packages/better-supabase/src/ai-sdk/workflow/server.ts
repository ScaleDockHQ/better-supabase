import {
  createModelCallToUIChunkTransform,
  type ModelCallStreamPart,
  normalizeUIMessageStreamParts,
} from "@ai-sdk/workflow";
import {
  JsonToSseTransformStream,
  UI_MESSAGE_STREAM_HEADERS,
  type UIMessageChunk,
} from "ai";
import { getRun, resumeHook, start } from "workflow/api";

import type {
  AiChatRecord,
  AiToolApproval,
} from "../../blocks/ai-chat/ai-chat.ts";
import type { AiRun, AiRuns } from "../../blocks/ai-chat/durable.ts";
import type { StreamStore } from "../../streams/store.ts";
import type { Assistant, AssistantContext } from "../chat/assistant.ts";
import type { DurableResume, DurableTurnInput } from "./turn.ts";

import { isRecord } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { resumeFromStore, teeToStore } from "../../streams/tee.ts";
import { WORKFLOW_ATTRIBUTES } from "../../workflow-sdk/attributes.ts";
import { durableStopToken, durableTurnToken } from "./turn.ts";

/** Who asks, for one request, with the chat block's durable runs. */
export interface DurableChatContext extends AssistantContext {
  /** `createAiRuns` on the same transports as `chats`. */
  readonly runs: AiRuns;
}

export interface DurableChatOptions {
  /** The assistant whose `prepare` checks and stores the user's turn. */
  readonly assistant: Pick<Assistant, "prepare">;
  /** The turn's `"use workflow"` function, which calls `durableTurn`. */
  readonly workflow: (input: DurableTurnInput) => Promise<unknown>;
  /** Keeps a copy of each segment the client reads, for when the World's stream is unavailable. */
  readonly streams: StreamStore;
  /** What the copy is kept for: seconds or a Postgres interval. Defaults to one day. */
  readonly streamTtl?: number | string;
  /** Makes message and stream ids. Defaults to `crypto.randomUUID()`. */
  readonly generateId?: () => string;
}

/** A decision the client or an approval inbox sends. */
export interface DurableApprovalDecision {
  readonly approvalId: string;
  readonly approved: boolean;
  readonly reason?: string;
}

export interface DurableChat {
  /**
   * The POST route. A new user message starts the turn's workflow; a body
   * with `approvals` decides them and continues the waiting turn. Both
   * stream the segment (SSE) with the `x-workflow-run-id` header.
   */
  respond(request: Request, context: DurableChatContext): Promise<Response>;
  /**
   * The reconnect route (`GET /api/chat/:id/stream?startIndex=`): the chat's
   * running segment, or its last one, from UI chunk `startIndex`. The
   * stream store answers when the World's stream can't be read; 204 when
   * the chat has no durable run.
   */
  resume(
    chatId: string,
    context: DurableChatContext,
    options?: { readonly startIndex?: number; readonly signal?: AbortSignal },
  ): Promise<Response>;
  /** Stops the running segment through the turn's stop hook, or cancels the run when the hook is gone. */
  stop(chatId: string, context: DurableChatContext): Promise<Response>;
  /**
   * Decides approvals from outside the chat, such as an approval inbox, and
   * continues the turn once none of its approvals is pending. Answers
   * `{ continued, streamId }` as JSON.
   */
  decide(
    chatId: string,
    decisions: readonly DurableApprovalDecision[],
    context: DurableChatContext,
  ): Promise<Response>;
}

/** The response header that names the workflow run. */
export const WORKFLOW_RUN_ID_HEADER = "x-workflow-run-id";

const WORKFLOW_ENGINE = "workflow";

function badRequest(message: string): Response {
  return problemResponse(
    dbError("invalid_request", message, { code: "AI_CHAT_BAD_REQUEST" }),
  );
}

function busy(): Response {
  return problemResponse(
    dbError("conflict", "An answer is already being written.", {
      code: "AI_CHAT_BUSY",
    }),
  );
}

function notDurable(): Response {
  return problemResponse(
    dbError("conflict", "The approvals belong to no durable run.", {
      code: "AI_CHAT_NOT_DURABLE",
    }),
  );
}

async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return undefined;
  }
}

/** The `approvals` of a body, `undefined` when it has none, or a message for a malformed one. */
function decisionsOf(
  value: unknown,
): readonly DurableApprovalDecision[] | string | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length === 0)
    return "Expected a list of approvals.";
  const decisions: DurableApprovalDecision[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item["approvalId"] !== "string" ||
      typeof item["approved"] !== "boolean"
    )
      return "Expected approvals with an approvalId and approved.";
    const { reason } = item;
    decisions.push({
      approvalId: item["approvalId"],
      approved: item["approved"],
      ...(typeof reason === "string" ? { reason } : {}),
    });
  }
  return decisions;
}

function streamOf<T>(iterable: AsyncIterable<T>): ReadableStream<T> {
  const iterator = iterable[Symbol.asyncIterator]();
  return new ReadableStream<T>({
    async pull(controller) {
      const next = await iterator.next();
      if (next.done === true) controller.close();
      else controller.enqueue(next.value);
    },
    async cancel(reason) {
      await iterator.return?.(reason);
    },
  });
}

async function* chunksOf(
  stream: ReadableStream<UIMessageChunk>,
  signal?: AbortSignal,
): AsyncGenerator<UIMessageChunk> {
  const reader = stream.getReader();
  // getReadable takes no signal: cancelling the reader closes the World's stream.
  const cancel = (): void => {
    reader.cancel(signal?.reason).catch(() => undefined);
  };
  if (signal?.aborted === true) cancel();
  else signal?.addEventListener("abort", cancel, { once: true });
  try {
    for (;;) {
      const next = await reader.read();
      if (next.done) return;
      yield next.value;
    }
  } finally {
    signal?.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
}

/** A segment's World stream as UI chunks, with the answer's id on `start`. */
function segmentChunks(
  workflowRunId: string,
  streamId: string,
  messageId: string | undefined,
  uiStartIndex: number,
  signal?: AbortSignal,
): ReadableStream<UIMessageChunk> {
  const parts = getRun(workflowRunId).getReadable<ModelCallStreamPart>({
    namespace: streamId,
  });
  const chunks = parts
    .pipeThrough(createModelCallToUIChunkTransform({ uiStartIndex }))
    .pipeThrough(
      new TransformStream<UIMessageChunk, UIMessageChunk>({
        transform(chunk, controller) {
          controller.enqueue(
            chunk.type === "start" && messageId !== undefined
              ? { ...chunk, messageId }
              : chunk,
          );
        },
      }),
    );
  return streamOf(normalizeUIMessageStreamParts(chunksOf(chunks, signal)));
}

/** `stream` once its first chunk arrives, or `undefined` when reading it fails. */
async function opened<T>(
  stream: ReadableStream<T>,
): Promise<ReadableStream<T> | undefined> {
  const reader = stream.getReader();
  let first: ReadableStreamReadResult<T>;
  try {
    first = await reader.read();
  } catch {
    return undefined;
  }
  let pending: ReadableStreamReadResult<T> | undefined = first;
  return new ReadableStream<T>({
    async pull(controller) {
      const next = pending ?? (await reader.read());
      pending = undefined;
      if (next.done) controller.close();
      else controller.enqueue(next.value);
    },
    async cancel(reason) {
      await reader.cancel(reason);
    },
  });
}

function sse(stream: ReadableStream<string>, workflowRunId?: string): Response {
  return new Response(stream.pipeThrough(new TextEncoderStream()), {
    headers: {
      ...UI_MESSAGE_STREAM_HEADERS,
      ...(workflowRunId === undefined
        ? {}
        : { [WORKFLOW_RUN_ID_HEADER]: workflowRunId }),
    },
  });
}

/**
 * Durable chat routes on the Workflow SDK: each turn is a workflow run
 * (`durableTurn`), so an answer outlives the request, a reload replays it
 * and an approval can wait for hours. The chat's runs stay in `ai_runs`
 * with the workflow run id next to them.
 */
export function durableChat(options: DurableChatOptions): DurableChat {
  const newId = options.generateId ?? (() => crypto.randomUUID());

  function streamSegment(
    context: DurableChatContext,
    chat: Pick<AiChatRecord, "ownerId" | "organizationId">,
    workflowRunId: string,
    streamId: string,
    messageId: string | undefined,
  ): Response {
    const teed = teeToStore(
      options.streams,
      streamId,
      segmentChunks(workflowRunId, streamId, messageId, 0).pipeThrough(
        new JsonToSseTransformStream(),
      ),
      {
        owner: chat.ownerId,
        tenant: chat.organizationId,
        kind: "chat",
        ...(options.streamTtl === undefined ? {} : { ttl: options.streamTtl }),
      },
    );
    context.waitUntil?.(
      (async () => {
        await teed.persisted;
      })(),
    );
    return sse(teed.stream, workflowRunId);
  }

  async function startTurn(
    body: unknown,
    context: DurableChatContext,
  ): Promise<Response> {
    const turn = await options.assistant.prepare(body, context);
    if (turn instanceof Response) return turn;
    const { chat, model } = turn;
    const streamId = newId();
    const messageId = newId();
    const claim = await context.chats.runs.claim(chat.id, streamId, {
      model,
      messageId,
      engine: WORKFLOW_ENGINE,
    });
    if (!claim.ok) return problemResponse(claim.error);
    const runId = claim.data.runId;
    if (!claim.data.claimed || runId === undefined) return busy();
    const input: DurableTurnInput = {
      chatId: chat.id,
      organizationId: chat.organizationId,
      userId: context.userId,
      model,
      messageId,
      parentId: turn.parentId,
      runId,
      streamId,
      messages: turn.messages,
      providerOptions: turn.providerOptions,
    };
    let workflowRunId: string;
    try {
      const run = await start(options.workflow, [input], {
        attributes: {
          [WORKFLOW_ATTRIBUTES.tenant]: chat.organizationId,
          [WORKFLOW_ATTRIBUTES.actor]: context.userId,
          [WORKFLOW_ATTRIBUTES.key]: `ai-chat:${chat.id}`,
        },
      });
      workflowRunId = run.runId;
    } catch (cause) {
      await context.chats.runs.release(chat.id, streamId, {
        status: "error",
        error: String(cause),
      });
      return problemResponse(
        dbError("unexpected", "The answer could not be started.", {
          code: "AI_CHAT_RUN_FAILED",
        }),
      );
    }
    const attached = await context.runs.attach(runId, workflowRunId);
    if (!attached.ok) {
      // Without the link, stop and resume can't find the run: end it.
      await getRun(workflowRunId)
        .cancel()
        .catch(() => undefined);
      await context.chats.runs.release(chat.id, streamId, {
        status: "error",
        error: attached.error.message,
      });
      return problemResponse(attached.error);
    }
    return streamSegment(context, chat, workflowRunId, streamId, messageId);
  }

  /** The durable run the decided approvals belong to, or a problem. */
  async function runOf(
    context: DurableChatContext,
    decided: readonly AiToolApproval[],
  ): Promise<AiRun | Response> {
    const runId = decided.find((row) => row.runId !== undefined)?.runId;
    if (runId === undefined) return notDurable();
    const run = await context.runs.get(runId);
    if (!run.ok) return problemResponse(run.error);
    return run.data.engine === WORKFLOW_ENGINE &&
      run.data.externalRunId !== undefined
      ? run.data
      : notDurable();
  }

  /** Decides, then claims a segment and resumes the turn when nothing is pending. */
  async function continueTurn(
    chatId: string,
    decisions: readonly DurableApprovalDecision[],
    context: DurableChatContext,
  ): Promise<
    | Response
    | { readonly continued: false }
    | {
        readonly continued: true;
        readonly chat: AiChatRecord;
        readonly workflowRunId: string;
        readonly streamId: string;
        readonly messageId: string | undefined;
      }
  > {
    const chat = await context.chats.chats.get(chatId);
    if (!chat.ok) return problemResponse(chat.error);
    const decided: AiToolApproval[] = [];
    for (const decision of decisions) {
      const row = await context.chats.approvals.decide(
        decision.approvalId,
        decision.approved,
        decision.reason,
      );
      if (!row.ok) return problemResponse(row.error);
      if (row.data.chatId !== chatId)
        return badRequest("The approvals belong to another chat.");
      decided.push(row.data);
    }
    const run = await runOf(context, decided);
    if (run instanceof Response) return run;
    const all = await context.chats.approvals.list(chatId);
    if (!all.ok) return problemResponse(all.error);
    if (
      all.data.some((row) => row.runId === run.id && row.decision === "pending")
    )
      return { continued: false };
    const workflowRunId = run.externalRunId ?? "";
    const streamId = newId();
    const claim = await context.chats.runs.claim(chatId, streamId, {
      engine: WORKFLOW_ENGINE,
      externalRunId: workflowRunId,
      ...(run.model === undefined ? {} : { model: run.model }),
      ...(run.assistantMessageId === undefined
        ? {}
        : { messageId: run.assistantMessageId }),
    });
    if (!claim.ok) return problemResponse(claim.error);
    const runId = claim.data.runId;
    if (!claim.data.claimed || runId === undefined) return busy();
    const resume: DurableResume = { streamId, runId };
    try {
      await resumeHook(durableTurnToken(workflowRunId), resume);
    } catch (cause) {
      await context.chats.runs.release(chatId, streamId, {
        status: "error",
        error: String(cause),
      });
      return problemResponse(
        dbError("conflict", "The turn is no longer waiting.", {
          code: "AI_CHAT_NOT_WAITING",
        }),
      );
    }
    return {
      continued: true,
      chat: chat.data,
      workflowRunId,
      streamId,
      messageId: run.assistantMessageId,
    };
  }

  async function respond(
    request: Request,
    context: DurableChatContext,
  ): Promise<Response> {
    const body = await readJson(request);
    const approvals = decisionsOf(
      isRecord(body) ? body["approvals"] : undefined,
    );
    if (approvals === undefined) return startTurn(body, context);
    if (typeof approvals === "string") return badRequest(approvals);
    const chatId = isRecord(body) ? body["id"] : undefined;
    if (typeof chatId !== "string" || chatId === "")
      return badRequest("Expected the chat id.");
    const continued = await continueTurn(chatId, approvals, context);
    if (continued instanceof Response) return continued;
    if (!continued.continued)
      return problemResponse(
        dbError("conflict", "Other approvals of this answer are pending.", {
          code: "AI_APPROVALS_PENDING",
        }),
      );
    return streamSegment(
      context,
      continued.chat,
      continued.workflowRunId,
      continued.streamId,
      continued.messageId,
    );
  }

  /** The chat's running durable run, else its latest one. */
  async function latestRun(
    context: DurableChatContext,
    chat: AiChatRecord,
  ): Promise<AiRun | undefined | Response> {
    if (chat.activeRunId !== undefined) {
      const run = await context.runs.get(chat.activeRunId);
      if (!run.ok) return problemResponse(run.error);
      return run.data;
    }
    const runs = await context.runs.list({ chatId: chat.id, size: 1 });
    if (!runs.ok) return problemResponse(runs.error);
    return runs.data[0];
  }

  async function resume(
    chatId: string,
    context: DurableChatContext,
    resumeOptions: {
      readonly startIndex?: number;
      readonly signal?: AbortSignal;
    } = {},
  ): Promise<Response> {
    const chat = await context.chats.chats.get(chatId);
    if (!chat.ok)
      return chat.error.kind === "not_found"
        ? new Response(null, { status: 204 })
        : problemResponse(chat.error);
    const run = await latestRun(context, chat.data);
    if (run instanceof Response) return run;
    const streamId = run?.streamId;
    if (run === undefined || streamId === undefined)
      return new Response(null, { status: 204 });
    const startIndex = Math.max(0, Math.trunc(resumeOptions.startIndex ?? 0));
    if (run.engine === WORKFLOW_ENGINE && run.externalRunId !== undefined) {
      let live: ReadableStream<string> | undefined;
      try {
        live = await opened(
          segmentChunks(
            run.externalRunId,
            streamId,
            run.assistantMessageId,
            startIndex,
            resumeOptions.signal,
          ).pipeThrough(new JsonToSseTransformStream()),
        );
      } catch {
        live = undefined;
      }
      // Without the World's stream, the stream store has the copy the client read.
      if (live !== undefined) return sse(live, run.externalRunId);
    }
    const stored = await resumeFromStore(options.streams, streamId, {
      fromIdx: startIndex,
      ...(resumeOptions.signal === undefined
        ? {}
        : { signal: resumeOptions.signal }),
    });
    if (!stored.ok) return problemResponse(stored.error);
    return stored.data === undefined
      ? new Response(null, { status: 204 })
      : sse(stored.data, run.externalRunId);
  }

  async function stop(
    chatId: string,
    context: DurableChatContext,
  ): Promise<Response> {
    const stopped = await context.chats.runs.stop(chatId);
    if (!stopped.ok) return problemResponse(stopped.error);
    if (stopped.data === undefined) return new Response(null, { status: 204 });
    const run = await context.runs.get(stopped.data.runId);
    if (!run.ok) return problemResponse(run.error);
    const workflowRunId = run.data.externalRunId;
    if (workflowRunId === undefined) return new Response(null, { status: 204 });
    try {
      await resumeHook(durableStopToken(workflowRunId), {});
    } catch {
      let cancelled = true;
      try {
        await getRun(workflowRunId).cancel();
      } catch {
        cancelled = false;
      }
      await context.chats.runs.release(chatId, stopped.data.streamId, {
        status: "stopped",
      });
      if (!cancelled)
        return problemResponse(
          dbError("unexpected", "The answer could not be stopped.", {
            code: "AI_CHAT_STOP_FAILED",
          }),
        );
    }
    return new Response(null, { status: 204 });
  }

  async function decide(
    chatId: string,
    decisions: readonly DurableApprovalDecision[],
    context: DurableChatContext,
  ): Promise<Response> {
    if (decisions.length === 0) return badRequest("Expected approvals.");
    const continued = await continueTurn(chatId, decisions, context);
    if (continued instanceof Response) return continued;
    return Response.json(
      continued.continued
        ? { continued: true, streamId: continued.streamId }
        : { continued: false },
    );
  }

  return { respond, resume, stop, decide };
}
