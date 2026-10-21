import type {
  QueueBackend,
  QueueMessageRow,
} from "../../blocks/jobs/backends.ts";
import type { Job } from "../../blocks/jobs/types.ts";

import { temporal } from "../../core/temporal-required.ts";
import {
  conform,
  expect,
  same,
  type ConformanceReport,
} from "../conformance.ts";
import { hasName } from "./executor.ts";

export interface TestQueueBackendOptions {
  /** A queue the kit may fill and drain; use a fresh name per run. */
  readonly queue: string;
  /**
   * Check that a repeated dedupe key returns the first id. Defaults to
   * `backend.leases`.
   */
  readonly dedupe?: boolean;
}

function claimedJob(queue: string, row: QueueMessageRow): Job {
  const instant = temporal().Instant.fromEpochMilliseconds(0);

  return {
    id: Number(row.id),
    queue,
    payload: row.message?.payload,
    attempts: row.attempts,
    maxAttempts: row.message?.max_attempts ?? 5,
    enqueuedAt: instant,
    visibleUntil: instant,
    lastError: row.message?.last_error ?? null,
    context: {},
  };
}

/**
 * Proves a `QueueBackend` round-trips payloads, hides claimed messages for
 * their lease, counts attempts, retries and dead-letters on `fail`, and (when
 * it has `leases`) rejects a stale attempt and extends a lease. It writes to
 * `options.queue` on the backend's real store.
 */
export function testQueueBackend(
  backend: QueueBackend,
  options: TestQueueBackendOptions,
): Promise<ConformanceReport> {
  const { queue } = options;

  const claimOne = async (): Promise<Job | undefined> => {
    const [row] = await backend.read(queue, 30, 1);

    return row && claimedJob(queue, row);
  };

  return conform(`QueueBackend "${backend.name}"`, [
    hasName(backend),
    [
      "has apiVersion 1",
      () => {
        const version: unknown = backend.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "round-trips a payload and leases it",
      async () => {
        const id = await backend.send(queue, { n: 1 }, 0, 3, undefined);
        expect(Number.isFinite(id), "send must return a numeric id");
        const job = await claimOne();
        expect(job?.id === id, "read must return the sent message");
        expect(same(job.payload, { n: 1 }), "the payload must round-trip");
        expect(job.attempts === 1, "the first claim must be attempt 1");
        expect(job.maxAttempts === 3, "max_attempts must round-trip");
        expect(
          (await claimOne()) === undefined,
          "a leased message must stay hidden from other reads",
        );
        expect(await backend.complete(job), "complete must return true");
      },
    ],
    backend.leases && [
      "rejects a stale attempt and extends a lease",
      async () => {
        await backend.send(queue, { n: 2 }, 0, 3, undefined);
        const job = await claimOne();
        expect(job, "read must return the sent message");
        expect(
          !(await backend.complete({ ...job, attempts: job.attempts + 1 })),
          "complete with another attempt must return false",
        );
        expect(await backend.extend(job, 60), "extend must return true");
        expect(await backend.complete(job), "complete must return true");
      },
    ],
    [
      "retries, then dead-letters at max attempts",
      async () => {
        await backend.send(queue, { n: 3 }, 0, 2, undefined);
        const first = await claimOne();
        expect(first, "read must return the sent message");
        expect(
          (await backend.fail(first, "boom", 0)) === "queued",
          "fail before max_attempts must return queued",
        );
        const second = await claimOne();
        expect(second?.attempts === 2, "a retried message must be attempt 2");
        expect(
          (await backend.fail(second, "boom", 0)) === "dead",
          "fail at max_attempts must return dead",
        );
        expect(
          (await claimOne()) === undefined,
          "a dead message must not be claimed again",
        );
      },
    ],
    backend.stats &&
      backend.listDead && [
        "counts and lists dead letters",
        async () => {
          const stats = await backend.stats?.(queue);
          expect((stats?.dead ?? 0) >= 1, "stats must count the dead letter");
          const [dead] = (await backend.listDead?.(queue, 10, undefined)) ?? [];
          expect(dead, "listDead must return the dead letter");
          expect(
            same(dead.message?.payload, { n: 3 }),
            "listDead must return the newest dead letter first",
          );

          if (backend.retryDead) {
            expect(
              (await backend.retryDead(queue, [Number(dead.id)], 10)) === 1,
              "retryDead must enqueue the dead letter again",
            );
            const job = await claimOne();
            expect(job, "the retried job must be claimable");
            expect(
              same(job.payload, { n: 3 }),
              "the retried job must keep its payload",
            );
            await backend.complete(job);
          }
        },
      ],
    (options.dedupe ?? backend.leases) && [
      "returns the first id for a repeated dedupe key",
      async () => {
        const first = await backend.send(queue, { n: 4 }, 0, 3, "same");
        const again = await backend.send(queue, { n: 4 }, 0, 3, "same");
        expect(first === again, "a waiting dedupe key must return its id");
        const job = await claimOne();
        expect(job, "read must return the sent message");
        await backend.complete(job);
      },
    ],
    backend.sendOnce && [
      "sends once per key, counting completed messages, when it has sendOnce",
      async () => {
        const key = `once-${Date.now()}`;
        const first = await backend.sendOnce?.(queue, { n: 5 }, 0, 3, key);
        expect(first && !first.duplicate, "the first sendOnce must send");
        const job = await claimOne();
        expect(job?.id === first.id, "read must return the sent message");
        await backend.complete(job);
        const again = await backend.sendOnce?.(queue, { n: 5 }, 0, 3, key);
        expect(
          again?.duplicate === true && again.id === first.id,
          "sendOnce after completion must return the first id as a duplicate",
        );
      },
    ],
  ]);
}
