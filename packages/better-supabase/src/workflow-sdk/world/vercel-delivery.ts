import type { MessageId, QueueBatchResult } from "@workflow/world";

import type { Logger } from "../../core/logger.ts";
import type { DeadLetter, StoredMessage } from "./types.ts";
import type {
  VercelDeliveryMetadata,
  VercelQueueSdk,
  VercelRetryDirective,
} from "./vercel-queue.ts";

import { MAX_DELIVERIES } from "./types.ts";
import {
  chainDelay,
  retentionFor,
  retryAfterSeconds,
  vercelIdempotencyKey,
  vercelTopicOf,
} from "./vercel-queue.ts";

/** A failed Vercel Queues delivery, with the message `retry` dead-letters. */
class DeliveryFailure extends Error {
  readonly stored: StoredMessage;
  readonly attempt: number;

  constructor(
    message: string,
    stored: StoredMessage,
    attempt: number,
    cause?: unknown,
  ) {
    super(message, { cause });
    this.stored = stored;
    this.attempt = attempt;
  }
}

/** The `timeoutSeconds` a successful flow response asks to wait. */
export function timeoutOf(text: string): number | undefined {
  try {
    const parsed: unknown = JSON.parse(text);

    if (
      typeof parsed === "object" &&
      parsed !== null &&
      "timeoutSeconds" in parsed
    ) {
      const value = Number(parsed.timeoutSeconds);

      if (Number.isFinite(value) && value >= 0) {
        return value;
      }
    }
  } catch {
    return undefined;
  }

  return undefined;
}

export interface VercelDeliveryDeps {
  readonly sdk: () => Promise<VercelQueueSdk>;
  readonly logger: Logger;
  /** The queue name `onDeadLetter` reports when the message has none. */
  readonly queueName: string;
  readonly deadLetter: (info: DeadLetter) => Promise<void>;
  /** Clears the run's owed wake-up after a completed orchestrator delivery. */
  readonly clearWake: (message: StoredMessage) => Promise<void>;
  readonly headers: (
    message: StoredMessage,
    attempt: number,
    deliveryCount: number,
  ) => Headers;
  readonly flowUrl: () => string;
  readonly isStoredMessage: (value: unknown) => value is StoredMessage;
  readonly runIdOf: (message: StoredMessage) => string | undefined;
  readonly backoffSeconds: (attempt: number) => number;
}

export interface VercelDelivery {
  /** One message; a delay past 23 hours goes in hops. */
  send(
    message: StoredMessage,
    delaySeconds: number | undefined,
    opts?: { readonly continuation?: boolean },
  ): Promise<void>;
  /**
   * Up to 100 messages per request; a failure is reported per message so the
   * runtime resends what did not go.
   */
  sendBatch(
    prepared: readonly {
      readonly messageId: MessageId;
      readonly stored: StoredMessage;
      readonly delay: number;
    }[],
  ): Promise<QueueBatchResult[]>;
  /**
   * The flow route's handler for Vercel Queues pushes: `handleCallback`
   * authenticates the request, a failed delivery backs off, and the message is
   * acknowledged and dead-lettered after `MAX_DELIVERIES` deliveries.
   */
  handler(
    inner: (req: Request) => Promise<Response>,
  ): (req: Request) => Promise<Response>;
}

function failedSend(cause: unknown): QueueBatchResult {
  return {
    messageId: null,
    error: cause instanceof Error ? cause.message : String(cause),
    retryable: true,
  };
}

/** The key of a message hop: a delayed hop must not collide with its first. */
function hopKey(message: StoredMessage, remaining: number): Promise<string> {
  const key = message.idempotencyKey ?? message.messageId;

  return vercelIdempotencyKey(
    remaining > 0 ? `${key}:hop:${String(remaining)}` : key,
  );
}

export function createVercelDelivery(deps: VercelDeliveryDeps): VercelDelivery {
  const send = async (
    message: StoredMessage,
    delaySeconds: number | undefined,
    opts?: { readonly continuation?: boolean },
  ): Promise<void> => {
    const sdk = await deps.sdk();
    const { delaySeconds: hop, remaining } = chainDelay(delaySeconds ?? 0);
    const retention = retentionFor(hop);

    await sdk.send(
      vercelTopicOf(message.queueName),
      remaining > 0 ? { ...message, remainingDelay: remaining } : message,
      {
        delaySeconds: hop,
        ...(opts?.continuation === true
          ? {}
          : { idempotencyKey: await hopKey(message, remaining) }),
        ...(retention === undefined ? {} : { retentionSeconds: retention }),
      },
    );
  };

  const sendBatch: VercelDelivery["sendBatch"] = async (prepared) => {
    const results: QueueBatchResult[] = [];

    try {
      const sdk = await deps.sdk();

      for (let from = 0; from < prepared.length; from += 100) {
        const chunk = prepared.slice(from, from + 100);
        const topic = vercelTopicOf(chunk[0]?.stored.queueName ?? "");

        if (sdk.sendBatch === undefined) {
          results.push(
            ...(await Promise.all(
              chunk.map(
                async ({
                  messageId,
                  stored,
                  delay,
                }): Promise<QueueBatchResult> => {
                  try {
                    await send(stored, delay);

                    return { messageId };
                  } catch (cause) {
                    return failedSend(cause);
                  }
                },
              ),
            )),
          );
          continue;
        }

        const messages = await Promise.all(
          chunk.map(async ({ stored, delay }) => {
            const { delaySeconds, remaining } = chainDelay(delay);
            const retention = retentionFor(delaySeconds);

            return {
              payload:
                remaining > 0
                  ? { ...stored, remainingDelay: remaining }
                  : stored,
              delaySeconds,
              idempotencyKey: await hopKey(stored, remaining),
              ...(retention === undefined
                ? {}
                : { retentionSeconds: retention }),
            };
          }),
        );

        const outcomes = await sdk.sendBatch(topic, messages);

        for (const [index, { messageId }] of chunk.entries()) {
          const outcome = outcomes[index];

          if (outcome === undefined) {
            results.push({
              messageId: null,
              error: "Queue batch returned no result for this message",
              retryable: true,
            });
          } else if (outcome.status === "failed") {
            results.push({
              messageId: null,
              error: outcome.error,
              retryable: outcome.retryable ?? true,
            });
          } else {
            results.push({ messageId });
          }
        }
      }
    } catch (cause) {
      return prepared.map(() => failedSend(cause));
    }

    return results;
  };

  const retry = (
    error: unknown,
    metadata: VercelDeliveryMetadata,
  ): VercelRetryDirective => {
    const failure = error instanceof DeliveryFailure ? error : undefined;
    const attempt = failure?.attempt ?? metadata.deliveryCount;

    if (metadata.deliveryCount >= MAX_DELIVERIES) {
      void deps.deadLetter({
        queueName: failure?.stored.queueName ?? deps.queueName,
        jobId: metadata.messageId,
        messageId: failure?.stored.messageId ?? metadata.messageId,
        ...(failure === undefined
          ? {}
          : { runId: deps.runIdOf(failure.stored) }),
        attempts: metadata.deliveryCount,
        error: error instanceof Error ? error.message : String(error),
      });

      return { acknowledge: true };
    }

    return { afterSeconds: retryAfterSeconds(deps.backoffSeconds(attempt)) };
  };

  const handler: VercelDelivery["handler"] = (inner) => {
    let callback: ReturnType<VercelQueueSdk["handleCallback"]> | undefined;

    const deliver = async (
      message: unknown,
      metadata: VercelDeliveryMetadata,
    ): Promise<void> => {
      if (!deps.isStoredMessage(message)) {
        deps.logger.error("Dropped a message that is not a workflow message", {
          messageId: metadata.messageId,
        });

        return;
      }

      if (message.remainingDelay !== undefined && message.remainingDelay > 0) {
        const { remainingDelay, ...next } = message;
        // Unkeyed: a continuation's hops share the key of the original
        // message's hops, and a duplicate wake is harmless where a dropped
        // one strands the run.
        await send(next, remainingDelay, { continuation: true });

        return;
      }

      const attempt = message.attempt + metadata.deliveryCount - 1;
      let status: number;
      let text: string;

      try {
        const response = await inner(
          new Request(deps.flowUrl(), {
            method: "POST",
            headers: deps.headers(message, attempt, metadata.deliveryCount),
            body: Buffer.from(message.body, "base64"),
          }),
        );

        status = response.status;
        text = await response.text();
      } catch (cause) {
        throw new DeliveryFailure(
          cause instanceof Error ? cause.message : String(cause),
          message,
          attempt,
          cause,
        );
      }

      if (status < 200 || status >= 300) {
        throw new DeliveryFailure(
          `Flow route answered ${String(status)}: ${text}`,
          message,
          attempt,
        );
      }

      const timeoutSeconds = timeoutOf(text);

      if (timeoutSeconds === undefined) {
        await deps.clearWake(message);
      } else {
        // A continuation is a new message, so `attempt` starts over (core
        // fails a run past 48 deliveries of one message) and it carries no
        // idempotency key: Vercel drops a send whose key it saw in the last
        // 24 hours, which is the key of the delivery that is answering now.
        await send({ ...message, attempt: 1 }, timeoutSeconds, {
          continuation: true,
        });
      }
    };

    return async (req) => {
      callback ??= (await deps.sdk()).handleCallback(deliver, { retry });

      return callback(req);
    };
  };

  return { send, sendBatch, handler };
}
