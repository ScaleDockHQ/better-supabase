import { createHook, sleep } from "workflow";
import { resumeHook } from "workflow/api";

/** How `approvalWaiter.wait` ended. */
export type ApprovalWaitResult<P> =
  | { readonly status: "resumed"; readonly payload: P }
  | { readonly status: "expired" };

export interface ApprovalWaitOptions {
  /** When the wait expires: a `Temporal.Instant` or an RFC 3339 timestamp. */
  readonly expiresAt: Temporal.Instant | string;
}

/**
 * Pauses a workflow on an approval and resumes it by token. `wait` runs
 * inside a `"use workflow"` function; `wake` runs in server code, after
 * the approver was checked (`authorizeHook`, or the provider's
 * `approverOf`). The token is the approval request's id, so the code that
 * records the decision can wake the run without storing the hook.
 */
export interface ApprovalWaiter {
  /**
   * Waits for `wake(token, payload)` until `expiresAt`: `{ status:
   * "resumed", payload }`, or `{ status: "expired" }` when the time passes
   * first (at once for a past `expiresAt`).
   */
  wait<P = unknown>(
    token: string,
    options: ApprovalWaitOptions,
  ): Promise<ApprovalWaitResult<P>>;
  /** Resumes the run waiting on `token`; `payload` defaults to `null`. */
  wake(token: string, payload?: unknown): Promise<void>;
}

const RFC_3339 =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u;

function tokenOf(token: string): string {
  if (token === "") throw new TypeError("An approval token is non-empty");
  return token;
}

function epochOf(expiresAt: Temporal.Instant | string): number {
  if (typeof expiresAt !== "string") return expiresAt.epochMilliseconds;
  const text = expiresAt.toUpperCase();
  const epoch = RFC_3339.test(text) ? Date.parse(text) : Number.NaN;
  if (Number.isNaN(epoch)) {
    throw new TypeError(
      `expiresAt "${expiresAt}" is not an RFC 3339 timestamp`,
    );
  }
  return epoch;
}

/** `wait` and `wake` for approvals that pause a workflow run. */
export const approvalWaiter: ApprovalWaiter = Object.freeze({
  async wait<P = unknown>(
    token: string,
    options: ApprovalWaitOptions,
  ): Promise<ApprovalWaitResult<P>> {
    const key = tokenOf(token);
    const until = epochOf(options.expiresAt);
    // The workflow runtime replays Date.now() from the event log, so the
    // comparison is deterministic and Temporal need not exist in its sandbox.
    if (until <= Date.now()) return { status: "expired" };
    const hook = createHook<P>({ token: key });
    try {
      return await Promise.race([
        hook.then((payload): ApprovalWaitResult<P> => ({
          status: "resumed",
          payload,
        })),
        sleep(new Date(until)).then((): ApprovalWaitResult<P> => ({
          status: "expired",
        })),
      ]);
    } finally {
      hook.dispose();
    }
  },
  async wake(token: string, payload: unknown = null): Promise<void> {
    await resumeHook(tokenOf(token), payload);
  },
});
