import type { AiChat } from "../../blocks/ai-chat/ai-chat.ts";
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

import { runRelease } from "../gateway.ts";
import { AI_SDK_UI_FORMAT, toUIMessage } from "../messages.ts";

export interface DurableStepOptions {
  /** Called with the cost backfill payload when the gateway hasn't reported a cost yet. */
  readonly enqueueCostBackfill?: (
    payload: CostBackfillPayload,
  ) => Promise<unknown>;
}

/**
 * Saves a turn's answer (service role) with its AI SDK form next to the
 * canonical one. The message id is the idempotency key: a retried step, or
 * the save after the next agent pass, updates the same message.
 */
export async function saveMessagesStep(
  chats: AiChat,
  input: DurableSaveInput,
): Promise<void> {
  await chats.messages
    .saveAssistant(input.chatId, input.message, {
      parentId: input.parentId,
      status: input.status,
      model: input.model,
      format: AI_SDK_UI_FORMAT,
      native: toUIMessage(input.message),
      runId: input.runId,
    })
    .orThrow();
}

async function recordApprovals(
  chats: AiChat,
  input: DurableApprovalsInput,
): Promise<void> {
  for (const request of input.requests)
    await chats.approvals
      .request(input.chatId, {
        approvalId: request.approvalId,
        tool: request.toolName,
        toolCallId: request.toolCallId,
        input: request.input,
        runId: input.runId,
        messageId: input.messageId,
        ...(request.signature === undefined
          ? {}
          : { signature: request.signature }),
      })
      .orThrow();
}

async function decisionsOf(
  chats: AiChat,
  input: DurableDecisionsInput,
): Promise<DurableDecision[]> {
  const rows = await chats.approvals
    .list(input.chatId, input.approvalIds)
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
    .release(
      input.chatId,
      input.streamId,
      runRelease(input.status, input.usage, input.error),
    )
    .orThrow();
  const { usage } = input;
  if (
    usage?.costMicroUsd === undefined &&
    usage?.generationId !== undefined &&
    options.enqueueCostBackfill
  )
    await options.enqueueCostBackfill({
      generationId: usage.generationId,
      organizationId: input.organizationId,
    });
}

/** A durable turn's database steps on a chat block's service transport. */
export function durableSteps(
  chats: AiChat,
  options: DurableStepOptions = {},
): DurableStepCalls {
  return {
    save: (input) => saveMessagesStep(chats, input),
    approvals: (input) => recordApprovals(chats, input),
    decisions: (input) => decisionsOf(chats, input),
    release: (input) => release(chats, input, options),
  };
}

/**
 * Runs one of a durable turn's database steps. Call it from the app's one
 * `"use step"` function, so the Workflow SDK records and retries each call;
 * a database error throws, which retries the step.
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
