import type { ModelCallStreamPart } from "@ai-sdk/workflow";
import type { UIMessageChunk } from "ai";

import {
  createModelCallToUIChunkTransform,
  normalizeUIMessageStreamParts,
} from "@ai-sdk/workflow";
import { FatalError, RetryableError } from "workflow";
import { getRun } from "workflow/api";

import type { AiChat } from "../../blocks/ai-chat/ai-chat.ts";
import type { AiDataPart, AiMessage } from "../../blocks/ai-chat/message.ts";
import type { DbErrorKind } from "../../core/errors.ts";
import type { CostBackfillPayload } from "../gateway.ts";
import type {
  DurableApprovalsInput,
  DurableDecision,
  DurableDecisionsInput,
  DurableReleaseInput,
  DurableSaveInput,
  DurableStepCalls,
  DurableStepInput,
  DurableStepName,
  DurableStepOutput,
} from "./turn.ts";

import { isRecord } from "../../core/block-helpers.ts";
import { DbException } from "../../core/db-exception.ts";
import { runRelease } from "../gateway.ts";
import { AI_SDK_UI_FORMAT, toUIMessage } from "../messages.ts";

export interface DurableStepOptions {
  /**
   * Called with the cost backfill payload when the gateway hasn't reported a
   * cost yet.
   */
  readonly enqueueCostBackfill?: (
    payload: CostBackfillPayload,
  ) => Promise<unknown>;
}

interface UIExtras {
  readonly data: AiDataPart[];
  readonly metadata: Record<string, unknown>;
}

/**
 * The chunks of `stream`, one at a time.
 *
 * @yields {UIMessageChunk} Each chunk, until the stream ends.
 */
async function* chunksOf(
  stream: ReadableStream<UIMessageChunk>,
): AsyncGenerator<UIMessageChunk> {
  const reader = stream.getReader();

  for (;;) {
    const next = await reader.read();

    if (next.done) {
      return;
    }

    yield next.value;
  }
}

/**
 * What only the UI stream carries: the persistent `data-*` parts and the
 * message metadata of every segment. `undefined` when a stream can't be read;
 * the answer is then saved from the model messages alone.
 */
async function uiExtras(
  workflowRunId: string,
  streamIds: readonly string[],
): Promise<UIExtras | undefined> {
  const data = new Map<string, AiDataPart>();
  const metadata: Record<string, unknown> = {};

  try {
    for (const namespace of streamIds) {
      const chunks = getRun(workflowRunId)
        .getReadable<ModelCallStreamPart>({ namespace })
        .pipeThrough(createModelCallToUIChunkTransform());

      for await (const chunk of normalizeUIMessageStreamParts(
        chunksOf(chunks),
      )) {
        if (
          chunk.type === "message-metadata" &&
          isRecord(chunk.messageMetadata)
        ) {
          Object.assign(metadata, chunk.messageMetadata);
        } else if (
          chunk.type.startsWith("data-") &&
          "data" in chunk &&
          !("transient" in chunk && chunk.transient)
        ) {
          const name = chunk.type.slice("data-".length);

          const id =
            "id" in chunk && typeof chunk.id === "string"
              ? chunk.id
              : undefined;

          // A later chunk with the same id replaces the earlier one, as in the client.
          data.set(`${name}:${id ?? data.size}`, {
            type: "data",
            name,
            ...(id === undefined ? {} : { id }),
            data: chunk.data,
          });
        }
      }
    }
  } catch {
    return undefined;
  }

  return { data: [...data.values()], metadata };
}

async function withExtras(input: DurableSaveInput): Promise<AiMessage> {
  if (input.streams === undefined) {
    return input.message;
  }

  const extras = await uiExtras(
    input.streams.workflowRunId,
    input.streams.streamIds,
  );

  if (extras === undefined) {
    return input.message;
  }

  const metadata = { ...input.message.metadata, ...extras.metadata };

  return {
    ...input.message,
    parts: [...input.message.parts, ...extras.data],
    ...(Object.keys(metadata).length === 0 ? {} : { metadata }),
  };
}

/** Failures a retry can't fix: the same call fails the same way. */
const PERMANENT_KINDS: ReadonlySet<DbErrorKind> = new Set<DbErrorKind>([
  "forbidden",
  "not_found",
  "validation",
  "conflict",
  "foreign_key",
  "check",
  "not_null",
  "exclusion",
  "invalid_input",
  "invalid_value",
  "invalid_request",
  "max_affected",
  "multiple_rows",
  "unsupported",
]);

/**
 * Maps a database failure to the Workflow SDK's step errors: a permanent one
 * (`forbidden`, `not_found`, `validation`, `conflict` and the other constraint
 * kinds) becomes a `FatalError` so the step stops retrying; `rate_limited` and
 * `quota_exceeded` become a `RetryableError` that waits their `retryAfter`. Any
 * other error (a network failure, a timeout) is returned as it is, so the step
 * keeps its default retries.
 */
export function durableStepError(error: unknown): unknown {
  if (!(error instanceof DbException)) {
    return error;
  }

  const { kind } = error.error;

  if (PERMANENT_KINDS.has(kind)) {
    return new FatalError(error.message);
  }

  if (kind === "rate_limited" || kind === "quota_exceeded") {
    const seconds =
      "retryAfter" in error.error ? error.error.retryAfter : undefined;

    return new RetryableError(
      error.message,
      seconds === undefined ? {} : { retryAfter: seconds * 1000 },
    );
  }

  return error;
}

async function mapped<T>(run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (error) {
    throw durableStepError(error);
  }
}

/**
 * Saves a turn's answer (service role) with its AI SDK form next to the
 * canonical one. The message id is the idempotency key: a retried step, or the
 * save after the next agent pass, updates the same message.
 */
export function saveMessagesStep(
  chats: AiChat,
  input: DurableSaveInput,
): Promise<void> {
  return mapped(() => saveMessages(chats, input));
}

async function saveMessages(
  chats: AiChat,
  input: DurableSaveInput,
): Promise<void> {
  const message = await withExtras(input);

  await chats.messages
    .saveAssistant({
      chatId: input.chatId,
      message,
      options: {
        parentId: input.parentId,
        status: input.status,
        model: input.model,
        format: AI_SDK_UI_FORMAT,
        native: toUIMessage(message),
        runId: input.runId,
      },
    })
    .orThrow();
}

async function recordApprovals(
  chats: AiChat,
  input: DurableApprovalsInput,
): Promise<void> {
  for (const request of input.requests) {
    await chats.approvals
      .request({
        chatId: input.chatId,
        request: {
          approvalId: request.approvalId,
          tool: request.toolName,
          toolCallId: request.toolCallId,
          input: request.input,
          runId: input.runId,
          messageId: input.messageId,
          ...(request.signature === undefined
            ? {}
            : { signature: request.signature }),
        },
      })
      .orThrow();
  }
}

async function decisionsOf(
  chats: AiChat,
  input: DurableDecisionsInput,
): Promise<DurableDecision[]> {
  const rows = await chats.approvals
    .list({ chatId: input.chatId, approvalIds: input.approvalIds })
    .orThrow();

  return rows.flatMap((row) =>
    row.decision === "pending"
      ? []
      : [
          {
            approvalId: row.approvalId,
            approved: row.decision === "approved",
            ...(row.reason === undefined ? {} : { reason: row.reason }),
          },
        ],
  );
}

async function release(
  chats: AiChat,
  input: DurableReleaseInput,
  options: DurableStepOptions,
): Promise<void> {
  await chats.runs
    .release({
      chatId: input.chatId,
      streamId: input.streamId,
      ...runRelease(input.status, input.usage, input.error),
    })
    .orThrow();
  const { usage } = input;

  if (
    usage?.costMicroUsd === undefined &&
    usage?.generationId !== undefined &&
    options.enqueueCostBackfill
  ) {
    await options.enqueueCostBackfill({
      generationId: usage.generationId,
      ...(input.organizationId === undefined
        ? {}
        : { organizationId: input.organizationId }),
    });
  }
}

/** A durable turn's database steps on a chat block's service transport. */
export function durableSteps(
  chats: AiChat,
  options: DurableStepOptions = {},
): DurableStepCalls {
  return {
    save: (input) => saveMessagesStep(chats, input),
    approvals: (input) => mapped(() => recordApprovals(chats, input)),
    decisions: (input) => mapped(() => decisionsOf(chats, input)),
    release: (input) => mapped(() => release(chats, input, options)),
  };
}

/**
 * Runs one of a durable turn's database steps. Call it from the app's one `"use
 * step"` function, so the Workflow SDK records and retries each call; a
 * permanent database error throws a `FatalError`, a rate limit a
 * `RetryableError`, and any other error retries the step.
 */
export function runDurableStep<K extends DurableStepName>(
  chats: AiChat,
  name: K,
  input: DurableStepInput<K>,
  options: DurableStepOptions = {},
): Promise<DurableStepOutput<K>> {
  const calls: DurableStepCalls = durableSteps(chats, options);

  return calls[name](input);
}
