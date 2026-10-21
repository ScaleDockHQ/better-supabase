import type { PollingQueueClient } from "@vercel/queue";

import { describe, expect, it } from "vitest";

import type {
  VercelQueueClient,
  VercelQueueMetadata,
} from "../../../src/blocks/jobs/vercel-queue.ts";

import { vercelQueueBackend } from "../../../src/blocks/jobs/vercel-queue.ts";
import { testQueueBackend } from "../../../src/testing/index.ts";

interface Stored {
  readonly id: string;
  readonly body: unknown;
  visibleAt: number;
  deliveries: number;
  gone: boolean;
}

/**
 * A PollingQueueClient in memory: receive locks, runs handlers, then acks or
 * retries.
 */
function fakeClient(): VercelQueueClient {
  const topics = new Map<string, Stored[]>();
  let count = 0;

  return {
    send: async (topic, payload, options) => {
      count += 1;
      const list = topics.get(topic) ?? [];

      list.push({
        id: `m${count}`,
        body: payload,
        visibleAt: Date.now() + (options?.delaySeconds ?? 0) * 1000,
        deliveries: 0,
        gone: false,
      });
      topics.set(topic, list);

      return { messageId: `m${count}` };
    },
    receive: async (topic, _group, handler, options) => {
      const ready = (topics.get(topic) ?? [])
        .filter((entry) => !entry.gone && entry.visibleAt <= Date.now())
        .slice(0, options?.limit ?? 1);

      if (ready.length === 0) {
        return { ok: false };
      }

      await Promise.all(
        ready.map(async (entry) => {
          entry.deliveries += 1;
          entry.visibleAt = Date.now() + 60_000;

          const metadata: VercelQueueMetadata = {
            messageId: entry.id,
            deliveryCount: entry.deliveries,
            createdAt: new Date(),
            expiresAt: new Date(Date.now() + 1e6),
          };

          try {
            await handler(entry.body, metadata);
            entry.gone = true;
          } catch (error) {
            const directive = options?.retry?.(error, metadata);

            if (directive && "acknowledge" in directive) {
              entry.gone = true;
            } else {
              entry.visibleAt =
                Date.now() + (directive?.afterSeconds ?? 60) * 1000;
            }
          }
        }),
      );

      return { ok: true };
    },
  };
}

// The real client must fit the structural type.
export const fits = (client: PollingQueueClient): VercelQueueClient => client;

describe("vercelQueueBackend", () => {
  it("passes the queue backend conformance kit", async () => {
    const report = await testQueueBackend(
      vercelQueueBackend(fakeClient(), { retryAfter: 0, settle: 1 }),
      { queue: "conformance" },
    );

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("refuses a queue name Vercel Queues would reject", async () => {
    const backend = vercelQueueBackend(fakeClient());

    await expect(backend.send("bad name", {}, 0, 1, undefined)).rejects.toThrow(
      /topic names/,
    );
  });

  it("needs the SQL backend for schedules", () => {
    const backend = vercelQueueBackend(fakeClient());

    expect(() => backend.unschedule("x")).toThrow(/SQL connection/);
  });

  it("settles held messages, and ignores jobs it does not hold", async () => {
    const backend = vercelQueueBackend(fakeClient(), {
      retryAfter: 0,
      settle: 1,
    });

    const ghost = {
      queue: "q",
      id: "nope",
      attempts: 1,
      maxAttempts: 2,
    } as never;

    expect(await backend.complete(ghost)).toBe(false);
    expect(await backend.fail(ghost, "x", undefined)).toBeNull();
    expect(await backend.extend(ghost, 30)).toBe(false);

    for (const [attempts, expected] of [
      [1, "queued"],
      [2, "dead"],
    ] as const) {
      await backend.send("q", { n: attempts }, 0, 2, undefined);
      const [row] = await backend.read("q", 30, 1);

      expect(row).toBeDefined();

      const job = {
        queue: "q",
        id: row?.id,
        attempts,
        maxAttempts: 2,
      } as never;

      expect(await backend.fail(job, "boom", 0)).toBe(expected);
    }

    await backend.send("q", { n: 3 }, 0, 2, undefined);
    const [held] = await backend.read("q", 30, 1);

    expect(
      await backend.complete({
        queue: "q",
        id: held?.id,
        attempts: 1,
        maxAttempts: 2,
      } as never),
    ).toBe(true);
  });
});
