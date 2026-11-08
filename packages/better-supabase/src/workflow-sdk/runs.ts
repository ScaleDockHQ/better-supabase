import type { Run } from "workflow/api";

import { getRun, resumeHook } from "workflow/api";
import { HookNotFoundError } from "workflow/errors";

import type { VerifyOptions, WebhookInput } from "../core/signatures.ts";

import { verifyStripeWebhook } from "../blocks/webhooks/verify.ts";
import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { verifyWebhook } from "../core/signatures.ts";

export interface CancelRunsOptions {
  /** Recorded on each `run_cancelled` event (at most 512 characters). */
  readonly reason?: string;
  /** Cancels this many runs at a time. Defaults to 10. */
  readonly concurrency?: number;
}

export interface CancelRunsResult {
  readonly cancelled: readonly string[];
  readonly failed: readonly {
    readonly runId: string;
    readonly error: unknown;
  }[];
}

/**
 * Cancels each run, a few at a time; a run that fails to cancel is listed in
 * `failed` and does not stop the others.
 */
export async function cancelRuns(
  runIds: readonly string[],
  options: CancelRunsOptions = {},
): Promise<CancelRunsResult> {
  const cancelled: string[] = [];
  const failed: { runId: string; error: unknown }[] = [];
  const size = Math.max(1, Math.trunc(options.concurrency ?? 10));

  const cancelOptions =
    options.reason === undefined ? {} : { cancelReason: options.reason };

  for (let index = 0; index < runIds.length; index += size) {
    const batch = runIds.slice(index, index + size);

    const results = await Promise.allSettled(
      batch.map((runId) => getRun(runId).cancel(cancelOptions)),
    );

    for (const [position, result] of results.entries()) {
      const runId = batch[position] ?? "";

      if (result.status === "fulfilled") {
        cancelled.push(runId);
      } else {
        failed.push({ runId, error: result.reason });
      }
    }
  }

  return { cancelled, failed };
}

/**
 * The response header `resumeStreamResponse` sets to the stream's last chunk
 * index.
 */
export const STREAM_TAIL_INDEX_HEADER = "x-workflow-stream-tail-index";

export interface ResumeStreamOptions {
  /**
   * The chunk to start from: a client that reconnects passes the index after
   * the last chunk it read; a negative value reads the last N chunks.
   */
  readonly startIndex?: number;
  /** The run's named stream (`getWritable({ namespace })`). */
  readonly namespace?: string;
  readonly headers?: HeadersInit;
  /**
   * Pipes the chunks through this transform before they reach the client, such
   * as one that re-frames the workflow's bytes.
   */
  readonly transform?: TransformStream<Uint8Array, Uint8Array>;
  /**
   * Answers as `text/event-stream` (with `cache-control: no-cache,
   * no-transform` and `x-accel-buffering: no`) instead of
   * `application/octet-stream`. The chunks must already be SSE frames, or the
   * `transform` makes them so.
   */
  readonly sse?: boolean;
}

/**
 * The run's stream as a response, from `startIndex`, with the index of the
 * stream's last chunk in the `x-workflow-stream-tail-index` header, so a client
 * can resume where it stopped.
 */
export async function resumeStreamResponse(
  run: Pick<Run<unknown>, "getReadable"> | string,
  options: ResumeStreamOptions = {},
): Promise<Response> {
  const target = typeof run === "string" ? getRun(run) : run;

  const stream = target.getReadable<Uint8Array>({
    ...(options.startIndex === undefined
      ? {}
      : { startIndex: options.startIndex }),
    ...(options.namespace === undefined
      ? {}
      : { namespace: options.namespace }),
  });

  const headers = new Headers(options.headers);

  headers.set(STREAM_TAIL_INDEX_HEADER, String(await stream.getTailIndex()));

  if (options.sse) {
    if (!headers.has("content-type")) {
      headers.set("content-type", "text/event-stream; charset=utf-8");
    }

    if (!headers.has("cache-control")) {
      headers.set("cache-control", "no-cache, no-transform");
    }

    if (!headers.has("x-accel-buffering")) {
      headers.set("x-accel-buffering", "no");
    }
  } else if (!headers.has("content-type")) {
    headers.set("content-type", "application/octet-stream");
  }

  return new Response(
    options.transform ? stream.pipeThrough(options.transform) : stream,
    { headers },
  );
}

export type WebhookProvider = "stripe" | "standard-webhooks";

export interface ResumeHookFromWebhookOptions extends Pick<
  VerifyOptions,
  "tolerance" | "seen"
> {
  /** How the sender signs: `Stripe-Signature`, or Standard Webhooks (and Svix). */
  readonly provider: WebhookProvider;
  /** One secret, or several while you rotate them. */
  readonly secrets: string | readonly string[];
  /** Called with the cause of a 503 or 500 answer, so the app can log it. */
  readonly onError?: (cause: unknown) => void;
}

const UNAVAILABLE_CODES = new Set([
  "ECONNREFUSED",
  "ECONNRESET",
  "ETIMEDOUT",
  "ENOTFOUND",
  "EPIPE",
]);

function isUnavailable(cause: unknown): boolean {
  if (typeof cause !== "object" || cause === null) {
    return false;
  }

  const code = "code" in cause ? cause.code : undefined;

  if (typeof code === "string") {
    // 08xxx is a Postgres connection exception, 57P0x an operator shutdown.
    return (
      UNAVAILABLE_CODES.has(code) ||
      code.startsWith("08") ||
      code.startsWith("57P")
    );
  }

  const status = "status" in cause ? cause.status : undefined;

  return typeof status === "number" && status >= 500;
}

/**
 * Verifies a signed webhook, then resumes the hook `token` with its JSON
 * payload. Responds 401 for a bad signature, 409 for a replay `seen` caught,
 * 404 when no run waits on the token, 503 `WORKFLOW_UNAVAILABLE` when the World
 * or its storage can't be reached, 500 `WORKFLOW_RESUME_FAILED` for any other
 * error, and 202 once the run resumes.
 */
export async function resumeHookFromWebhook(
  input: WebhookInput,
  token: string,
  options: ResumeHookFromWebhookOptions,
): Promise<Response> {
  const verifyOptions: VerifyOptions = {
    ...(options.tolerance === undefined
      ? {}
      : { tolerance: options.tolerance }),
    ...(options.seen === undefined ? {} : { seen: options.seen }),
  };

  const verified =
    options.provider === "stripe"
      ? await verifyStripeWebhook(input, options.secrets, verifyOptions)
      : await verifyWebhook(input, options.secrets, verifyOptions);

  if (!verified.ok) {
    return problemResponse(verified.error, { expose: true });
  }

  try {
    await resumeHook(token, verified.data.payload);
  } catch (cause) {
    if (HookNotFoundError.is(cause)) {
      return problemResponse(
        dbError("not_found", "No workflow run waits on this hook", {
          code: "WORKFLOW_HOOK_NOT_FOUND",
        }),
        { expose: true },
      );
    }

    options.onError?.(cause);

    return problemResponse(
      isUnavailable(cause)
        ? dbError("network", "The workflow World is unavailable", {
            code: "WORKFLOW_UNAVAILABLE",
          })
        : dbError("unexpected", "The workflow run could not be resumed", {
            code: "WORKFLOW_RESUME_FAILED",
          }),
      { expose: true },
    );
  }

  return new Response(null, { status: 202 });
}
