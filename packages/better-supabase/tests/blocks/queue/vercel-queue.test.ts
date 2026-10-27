import type { PollingQueueClient, QueueClient } from "@vercel/queue";

import { describe, expect, it } from "vitest";

import type { Job } from "../../../src/blocks/queue/types.ts";
import type {
  VercelQueueClient,
  VercelQueueMetadata,
} from "../../../src/blocks/queue/vercel-queue.ts";

import { withDeadLetters } from "../../../src/blocks/queue/dead-letters.ts";
import {
  vercelIdempotencyKey,
  vercelQueueProvider,
  vercelQueueTriggers,
  vercelRetentionSeconds,
  vercelSendOptionsOf,
  vercelTopicOf,
} from "../../../src/blocks/queue/vercel-queue.ts";
import { testQueueProvider } from "../../../src/testing/index.ts";

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
export const pushFits = (client: QueueClient): VercelQueueClient => client;

describe("vercelQueueProvider", () => {
  it("passes the queue backend conformance kit", async () => {
    const report = await testQueueProvider(
      vercelQueueProvider(fakeClient(), { retryAfter: 0, settle: 1 }),
      { queue: "conformance" },
    );

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("refuses a queue name Vercel Queues would reject", async () => {
    const backend = vercelQueueProvider(fakeClient());

    await expect(backend.send("bad name", {}, 0, 1, undefined)).rejects.toThrow(
      /topic names/,
    );
  });

  it("keeps a delayed message an hour past its delay, within 7 days", async () => {
    expect(vercelRetentionSeconds(0)).toBeUndefined();
    expect(vercelRetentionSeconds(60)).toBe(86_400);
    expect(vercelRetentionSeconds(2 * 86_400)).toBe(2 * 86_400 + 3600);
    expect(vercelRetentionSeconds(7 * 86_400)).toBe(7 * 86_400);
    expect(() => vercelRetentionSeconds(7 * 86_400 + 1)).toThrow(/7 days/);

    const sent: unknown[] = [];

    const backend = vercelQueueProvider({
      ...fakeClient(),
      send: (_topic, _payload, options) => {
        sent.push(options);

        return Promise.resolve({ messageId: "m1" });
      },
    });

    await backend.send("q", {}, 2 * 86_400, 1, "k");
    expect(sent).toEqual([
      {
        delaySeconds: 2 * 86_400,
        retentionSeconds: 2 * 86_400 + 3600,
        idempotencyKey: "k",
      },
    ]);
  });

  it("reports each receive result", async () => {
    const results: unknown[] = [];

    const backend = vercelQueueProvider(fakeClient(), {
      settle: 1,
      onReceive: (queue, result) => results.push([queue, result]),
    });

    expect(await backend.read("q", 30, 1)).toEqual([]);
    expect(results).toEqual([["q", { ok: false }]]);
  });

  it("sends through a push client and refuses to poll with it", async () => {
    const backend = vercelQueueProvider({
      send: () => Promise.resolve({ messageId: "m1" }),
    });

    await expect(backend.read("q", 30, 1)).rejects.toThrow(/vercelQueueRoute/);
  });

  it("needs the SQL backend for schedules", () => {
    const backend = vercelQueueProvider(fakeClient());

    expect(() => backend.unschedule("x")).toThrow(/SQL connection/);
  });

  it("settles held messages, and ignores jobs it does not hold", async () => {
    const backend = vercelQueueProvider(fakeClient(), {
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

  it("maps queue names onto topics and reads with a group per queue", async () => {
    const sent: unknown[] = [];
    const groups: unknown[] = [];
    const client = fakeClient();

    const backend = vercelQueueProvider(
      {
        send: (topic, payload, options) => {
          sent.push([topic, options]);

          return client.send(topic, payload, options);
        },
        receive: (topic, group, handler, options) => {
          groups.push([topic, group]);

          return client.receive?.(topic, group, handler, options) ?? noReceive;
        },
      },
      {
        settle: 1,
        consumerGroup: (queue) => `workers-${vercelTopicOf(queue)}`,
        retention: 10,
        headers: { "x-app": "crm" },
      },
    );

    await backend.send("billing.invoice", {}, 0, 1, "k".repeat(300));
    expect(await backend.read("billing.invoice", 30, 1)).toHaveLength(1);
    expect(sent).toEqual([
      [
        "billing-invoice",
        {
          delaySeconds: 0,
          retentionSeconds: 60,
          idempotencyKey: expect.stringMatching(/^[0-9a-f]{64}$/),
          headers: { "x-app": "crm" },
        },
      ],
    ]);
    expect(groups).toEqual([["billing-invoice", "workers-billing-invoice"]]);
  });

  it("says where the counts are instead of returning stats", async () => {
    await expect(
      vercelQueueProvider(fakeClient()).stats?.("q"),
    ).rejects.toThrow(/Observability/);
  });
});

const noReceive = Promise.resolve({ ok: false } as const);

describe("Vercel Queues helpers", () => {
  it("maps queue names onto topic names", () => {
    expect(vercelTopicOf("tenant:sync.daily")).toBe("tenant-sync-daily");
    expect(() => vercelTopicOf("a b")).toThrow(/topic names/);
  });

  it("hashes idempotency keys past 256 characters", async () => {
    expect(await vercelIdempotencyKey("short")).toBe("short");
    expect(await vercelIdempotencyKey("x".repeat(257))).toMatch(
      /^[0-9a-f]{64}$/,
    );
  });

  it("clamps retention and keeps a delayed message past its delay", async () => {
    expect(await vercelSendOptionsOf(0, undefined)).toEqual({
      delaySeconds: 0,
    });
    expect(
      await vercelSendOptionsOf(0, undefined, { retention: 10 ** 9 }),
    ).toEqual({ delaySeconds: 0, retentionSeconds: 604_800 });
    expect(
      await vercelSendOptionsOf(7200, undefined, { retention: 120 }),
    ).toEqual({ delaySeconds: 7200, retentionSeconds: 10_800 });
    await expect(
      vercelSendOptionsOf(8 * 86_400, undefined, { retention: 120 }),
    ).rejects.toThrow(/7 days/);
  });

  it("writes the vercel.json triggers for a push route", () => {
    expect(
      vercelQueueTriggers("app/api/queues/route.ts", ["emails", "crm.sync"], {
        maxAttempts: { emails: 3 },
      }),
    ).toEqual({
      "app/api/queues/route.ts": {
        experimentalTriggers: [
          { type: "queue/v2beta", topic: "emails", maxDeliveries: 3 },
          { type: "queue/v2beta", topic: "crm-sync" },
        ],
      },
    });
    expect(
      vercelQueueTriggers("r.ts", ["a"], { maxAttempts: 5 })["r.ts"]
        ?.experimentalTriggers,
    ).toEqual([{ type: "queue/v2beta", topic: "a", maxDeliveries: 5 }]);
  });
});

describe("withDeadLetters", () => {
  it("hands a job past its last attempt to the sink", async () => {
    const dead: unknown[] = [];

    const backend = withDeadLetters(
      vercelQueueProvider(fakeClient(), { retryAfter: 0, settle: 1 }),
      {
        onDead: (job, error) => {
          dead.push([job.queue, error]);
          throw new Error("sink down");
        },
        listDead: () => Promise.resolve([]),
        retryDead: () => Promise.resolve(0),
      },
    );

    expect(backend.name).toBe("vercel-queues+dead-letters");

    for (const attempts of [1, 2]) {
      await backend.send("q", {}, 0, 2, undefined);
      const [row] = await backend.read("q", 30, 1);
      const job = { queue: "q", id: row?.id, attempts, maxAttempts: 2 };

      // SAFETY: fail reads only queue, id, attempts and maxAttempts.
      await backend.fail(job as Job, "boom", 0);
    }

    expect(dead).toEqual([["q", "boom"]]);
    expect(await backend.listDead?.("q", 10, undefined)).toEqual([]);
    expect(await backend.retryDead?.("q", undefined, 10)).toBe(0);
  });

  it("keeps the backend's own dead letters without a sink list", () => {
    const backend = withDeadLetters(vercelQueueProvider(fakeClient()), {
      onDead: () => undefined,
    });

    expect("listDead" in backend).toBe(false);
  });
});
