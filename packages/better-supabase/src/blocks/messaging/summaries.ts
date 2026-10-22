import type { Message } from "./messaging.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { optionalText, recordOf, requiredInstant, textOf } from "../shared.ts";
import { num } from "./rows.ts";

/** What a summary covers: a whole conversation or one thread. */
export type SummaryTarget =
  | { readonly conversationId: string }
  | { readonly threadId: string };

/**
 * A summary of a thread, or of a conversation's top-level messages. `stale`
 * turns true once a message in it is sent, edited or deleted after it.
 */
export interface ThreadSummary {
  readonly id: string;
  readonly organizationId: string;
  readonly conversationId: string;
  /** The thread's root message; `undefined` for a conversation's summary. */
  readonly threadId: string | undefined;
  readonly summary: string;
  /** The model the summarizer named, such as `anthropic/claude-sonnet-4.5`. */
  readonly model: string | undefined;
  readonly messageCount: number;
  /** When the newest summarized message was sent. */
  readonly throughAt: Temporal.Instant;
  readonly stale: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** One message a summarizer reads. */
export interface SummaryMessage {
  readonly id: string;
  readonly authorId: string | undefined;
  /** With the `profiles` module. */
  readonly authorName: string | undefined;
  readonly body: string;
  readonly sentAt: Temporal.Instant;
}

export interface ThreadSummaryInput {
  readonly organizationId: string;
  readonly conversationId: string;
  readonly threadId: string | undefined;
  /** Oldest first: the caller's sent messages, without internal notes. */
  readonly messages: readonly SummaryMessage[];
  /** The summary saved before, to update instead of starting over. */
  readonly previous: string | undefined;
  readonly signal?: AbortSignal;
}

export interface ThreadSummaryOutput {
  readonly summary: string;
  readonly model?: string;
}

/**
 * Writes a summary from a thread's messages. The block calls no model itself:
 * `summarizeWith(model)` from `better-supabase/ai-sdk` is one, and any object
 * with this shape is another.
 */
export interface ThreadSummarizer {
  readonly apiVersion: 1;
  summarize(input: ThreadSummaryInput): Promise<ThreadSummaryOutput>;
}

export interface SummarizeOptions {
  /** Summarizes again even when the saved summary is current. */
  readonly force?: boolean;
  /** The newest messages to read, at most 200. Default 200. */
  readonly maxMessages?: number;
  readonly signal?: AbortSignal;
}

/** The most messages one summary reads. */
const MAX_SUMMARY_MESSAGES = 200;

export function threadSummaryOf(value: unknown): ThreadSummary {
  const row = recordOf(value, "thread summary");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    conversationId: textOf(row["conversation_id"]),
    threadId: optionalText(row["thread_id"]),
    summary: textOf(row["summary"]),
    model: optionalText(row["model"]),
    messageCount: num(row["message_count"]),
    throughAt: requiredInstant(row["through_at"], "throughAt"),
    stale: row["stale"] === true,
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    updatedAt: requiredInstant(row["updated_at"], "updatedAt"),
  };
}

export interface SummarySteps {
  readonly current: (
    target: SummaryTarget,
  ) => AsyncResult<ThreadSummary | undefined>;
  /** The target's sent messages, oldest first, at most `max`. */
  readonly read: (
    target: SummaryTarget,
    max: number,
  ) => AsyncResult<readonly Message[]>;
  readonly save: (
    target: SummaryTarget,
    summary: ThreadSummaryOutput & {
      readonly messageCount: number;
      readonly throughAt: Temporal.Instant;
    },
  ) => AsyncResult<ThreadSummary>;
}

const summaryMessageOf = (message: Message): SummaryMessage => ({
  id: message.id,
  authorId: message.authorId,
  authorName: message.author?.name,
  body: message.body,
  // SAFETY: `read` returns sent messages only.
  sentAt: message.sentAt!,
});

/**
 * Returns the saved summary while it is current, or reads the messages as the
 * caller, asks `summarizer` and saves what it wrote.
 */
export function summarize(
  steps: SummarySteps,
  target: SummaryTarget,
  summarizer: ThreadSummarizer,
  options: SummarizeOptions = {},
): AsyncResult<ThreadSummary> {
  const max = Math.min(
    Math.max(Math.trunc(options.maxMessages ?? MAX_SUMMARY_MESSAGES), 1),
    MAX_SUMMARY_MESSAGES,
  );

  return steps.current(target).andThen((saved) => {
    if (saved !== undefined && !saved.stale && options.force !== true) {
      return AsyncResult.ok(saved);
    }

    return steps.read(target, max).andThen((read) => {
      const sent = read.filter(
        (message) =>
          message.kind === "message" &&
          message.sentAt !== undefined &&
          message.deletedAt === undefined &&
          message.body.trim() !== "",
      );

      const first = sent[0];

      if (first === undefined) {
        return AsyncResult.err(
          dbError("invalid_input", "There are no messages to summarize", {
            code: "MESSAGING_SUMMARY_EMPTY",
          }),
        );
      }

      const messages = sent.map(summaryMessageOf);
      // SAFETY: `messages` has the same length as `sent`, which has `first`.
      const newest = messages.at(-1)!;

      return AsyncResult.from(async () =>
        ok(
          await summarizer.summarize({
            organizationId: first.organizationId,
            conversationId: first.conversationId,
            threadId: "threadId" in target ? target.threadId : undefined,
            messages,
            previous: saved?.summary,
            ...(options.signal === undefined ? {} : { signal: options.signal }),
          }),
        ),
      ).andThen((output) =>
        steps.save(target, {
          ...output,
          messageCount: messages.length,
          throughAt: newest.sentAt,
        }),
      );
    });
  });
}
