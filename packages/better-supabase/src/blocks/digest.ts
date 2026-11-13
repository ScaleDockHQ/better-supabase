import type { AsyncResult } from "../core/result.ts";

import { ok } from "../core/result.ts";

/** A held entry a digest folds in: what it says and where it leads. */
export interface DigestLine {
  readonly label: string;
  readonly path?: string | undefined;
}

/** The plain text of a digest: one line per entry. */
export function digestLines(lines: readonly DigestLine[]): string {
  return lines
    .map(
      (line) =>
        `- ${line.label}${line.path === undefined ? "" : ` (${line.path})`}`,
    )
    .join("\n");
}

/** What one digest run did. */
export interface DigestRunReport {
  readonly claimed: number;
  readonly sent: number;
  readonly failed: number;
  readonly skipped: number;
}

/** What `runDigests` needs from a digest. */
export interface ClaimedDigest {
  readonly id: string;
  /** `null` skips the digest: there is nowhere to send it. */
  readonly email: string | null;
}

/** How `runDigests` reports each digest back to the block that claimed it. */
export type DigestOutcome =
  | { readonly status: "sent"; readonly providerMessageId: string }
  | { readonly status: "skipped"; readonly error: string }
  | { readonly status: "pending"; readonly error: string };

export interface DigestRunner<D extends ClaimedDigest> {
  /** Claims the digests that are due. */
  readonly claim: () => AsyncResult<readonly D[]>;
  /** Sends one digest; resolves with the provider's message id. */
  readonly send: (input: {
    readonly digest: D;
    readonly email: string;
  }) => Promise<
    | { readonly ok: true; readonly id: string }
    | { readonly ok: false; readonly error: string }
  >;
  /** Records the outcome of one digest. */
  readonly complete: (input: {
    readonly digest: D;
    readonly outcome: DigestOutcome;
  }) => AsyncResult<unknown>;
}

/**
 * Claims due digests, sends each to its address and records the outcome: a
 * digest without an address is `skipped`, a failed send goes back to `pending`
 * for the next run. A claim or completion error stops the run.
 */
export function runDigests<D extends ClaimedDigest>(
  runner: DigestRunner<D>,
): AsyncResult<DigestRunReport> {
  return runner.claim().andThen(async (digests) => {
    let sent = 0;
    let failed = 0;
    let skipped = 0;

    for (const digest of digests) {
      if (digest.email === null) {
        skipped += 1;

        const done = await runner.complete({
          digest,
          outcome: {
            status: "skipped",
            error: "The member has no email address",
          },
        });

        if (!done.ok) {
          return done;
        }

        continue;
      }

      const outcome = await runner.send({ digest, email: digest.email });

      const done = await runner.complete({
        digest,
        outcome: outcome.ok
          ? { status: "sent", providerMessageId: outcome.id }
          : { status: "pending", error: outcome.error },
      });

      if (!done.ok) {
        return done;
      }

      if (outcome.ok) {
        sent += 1;
      } else {
        failed += 1;
      }
    }

    return ok({ claimed: digests.length, sent, failed, skipped });
  });
}
