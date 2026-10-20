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

/** A PollingQueueClient in memory: receive locks, runs handlers, then acks or retries. */
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
});
