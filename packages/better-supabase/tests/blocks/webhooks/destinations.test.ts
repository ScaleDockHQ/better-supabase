import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { QueueBackend } from "../../../src/blocks/jobs/index.ts";
import type { IncomingDestination } from "../../../src/blocks/webhooks/index.ts";

import { createJobs } from "../../../src/blocks/jobs/index.ts";
import {
  createIncomingWebhooks,
  inboxDestination,
  jobsDestination,
} from "../../../src/blocks/webhooks/index.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testIncomingDestination } from "../../../src/testing/index.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";

/** A queue that dedupes `sendOnce` by key and records every payload. */
function onceBackend(withOnce = true) {
  const keys = new Map<string, number>();
  const sent: unknown[] = [];

  const backend: QueueBackend = {
    apiVersion: 1,
    name: "once",
    leases: true,
    send: () => Promise.resolve(1),
    read: () => Promise.resolve([]),
    complete: () => Promise.resolve(true),
    fail: () => Promise.resolve("queued"),
    extend: () => Promise.resolve(true),
    schedule: () => Promise.resolve(),
    unschedule: () => Promise.resolve(true),
    ...(withOnce
      ? {
          sendOnce(
            queue: string,
            payload: unknown,
            _d: number,
            _m: number,
            key: string,
          ) {
            const seen = keys.get(`${queue}:${key}`);

            if (seen !== undefined) {
              return Promise.resolve({ id: seen, duplicate: true });
            }

            const id = keys.size + 1;
            keys.set(`${queue}:${key}`, id);
            sent.push(payload);

            return Promise.resolve({ id, duplicate: false });
          },
        }
      : {}),
  };

  return { backend, sent };
}

describe("incoming destinations", () => {
  it("queues a delivery once per endpoint and message id with its tenant", async () => {
    const { backend, sent } = onceBackend();

    const jobs = createJobs({
      backend,
      queues: { leads: v.object({ type: v.string() }) },
    });

    const destination = jobsDestination(jobs, {
      queue: "leads",
      payload: (delivery) => ({ type: delivery.type ?? "unknown" }),
    });

    await testIncomingDestination(destination, { tenant: "t1" });
    expect(sent).toHaveLength(3);
    expect(sent[0]).toMatchObject({
      payload: { type: "conformance.test" },
      context: { tenant: "t1" },
    });
  });

  it("passes the kit on the inbox and keys messages by endpoint", async () => {
    const stored = new Map<string, number>();

    const fake = fakeSql([
      [
        "receive_webhook",
        (call) => {
          const key = `${String(call.values[0])}:${String(call.values[1])}:${String(call.values[5])}`;
          const seen = stored.get(key);

          if (seen !== undefined) {
            return [{ value: { id: seen, duplicate: true } }];
          }

          stored.set(key, stored.size + 1);

          return [{ value: { id: stored.size, duplicate: false } }];
        },
      ],
    ]);

    await testIncomingDestination(inboxDestination(fake.sql), {
      tenant: "t1",
      source: "forms",
    });
    const [first] = fake.calls;
    expect(first!.values[0]).toBe("forms");
    expect(String(first!.values[1])).toMatch(/^[0-9a-f-]{36}:m1$/);
    expect(first!.values[5]).toBe("t1");
  });

  it("fails the kit for a destination that never reports a duplicate", async () => {
    let next = 0;

    const forgetful: IncomingDestination = {
      apiVersion: 1,
      name: "forgetful",
      deliver: () => Promise.resolve({ id: ++next, duplicate: false }),
    };

    await expect(
      testIncomingDestination(forgetful, { tenant: "t1" }),
    ).rejects.toBeInstanceOf(ConformanceError);
  });

  it("refuses a queue backend without sendOnce", async () => {
    const jobs = createJobs({
      backend: onceBackend(false).backend,
      queues: {
        leads: v.object({}),
      },
    });

    await expect(
      jobsDestination(jobs, { queue: "leads", payload: () => ({}) }).deliver({
        endpoint: { id: "e1", tenant: "t1", metadata: {} },
        source: "s",
        messageId: "m1",
        type: null,
        payload: {},
        headers: {},
      }),
    ).rejects.toThrow(/enqueueOnce/);
  });

  it("hands verified deliveries with the endpoint's metadata to the destination", async () => {
    const fake = fakeSql([
      [
        "incoming_webhook_by_token",
        [
          {
            id: "e1",
            tenant: "t1",
            enabled: true,
            verify: "none",
            secret: null,
            signature_header: null,
            max_body_bytes: 100,
            metadata: { route: "leads" },
          },
        ],
      ],
    ]);

    const delivered: unknown[] = [];

    const hooks = createIncomingWebhooks({
      sql: fake.sql,
      source: "forms",
      destination: {
        apiVersion: 1,
        name: "memory",
        deliver(delivery) {
          delivered.push(delivery);

          return Promise.resolve({
            id: 1,
            duplicate: delivered.length > 1,
          });
        },
      },
    });

    const post = () =>
      hooks.receive(
        new Request("https://api.test/hooks/tok", {
          method: "POST",
          headers: { "webhook-id": "m1" },
          body: '{"type":"lead.created"}',
        }),
        "tok",
      );

    expect((await post()).status).toBe(202);
    expect((await post()).status).toBe(200);
    expect(delivered[0]).toMatchObject({
      endpoint: { id: "e1", tenant: "t1", metadata: { route: "leads" } },
      source: "forms",
      type: "lead.created",
      payload: { type: "lead.created" },
    });
    expect(fake.texts().some((text) => text.includes("receive_webhook"))).toBe(
      false,
    );
  });
});
