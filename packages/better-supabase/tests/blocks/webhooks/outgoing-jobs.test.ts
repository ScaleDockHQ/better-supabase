import { describe, expect, it } from "vitest";

import { createWebhooks } from "../../../src/blocks/webhooks/index.ts";
import { createJobs } from "../../../src/core/jobs.ts";

const delivery = (overrides: Record<string, unknown> = {}) => ({
  id: "d1",
  endpointId: "e1",
  type: "invoice.paid",
  status: "pending",
  attempt: 0,
  responseStatus: null,
  durationMs: null,
  lastError: null,
  processedAt: null,
  createdAt: "2026-11-15T10:00:00Z",
  ...overrides,
});

function webhooks(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  const client = createWebhooks({
    transport: {
      call(_schema, fn, args) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  });

  return { calls, client, jobs: createJobs({ webhook: client.jobs }) };
}

describe("webhook jobs", () => {
  it("starts a dispatch and a redelivery as a job", async () => {
    const { calls, client } = webhooks({
      dispatch_webhook: "d1",
      redeliver_webhook: "d2",
    });

    expect(
      await client
        .dispatchJob({ endpointId: "e1", type: "invoice.paid", data: {} })
        .orThrow(),
    ).toEqual({ jobId: "webhook:d1" });
    expect(await client.redeliverJob("d2").orThrow()).toEqual({
      jobId: "webhook:d2",
    });
    expect(calls.map(([fn]) => fn)).toEqual([
      "dispatch_webhook",
      "redeliver_webhook",
    ]);
  });

  it("maps each delivery status to a job status", async () => {
    const read = async (row: Record<string, unknown>) =>
      webhooks({ get_webhook_delivery: delivery(row) })
        .jobs.get("webhook:d1")
        .orThrow();

    expect(await read({})).toMatchObject({
      status: "pending",
      done: false,
      progress: null,
    });
    expect(await read({ status: "retrying", attempt: 2 })).toMatchObject({
      status: "running",
      done: false,
    });
    expect(await read({ status: "delivering" })).toMatchObject({
      status: "running",
    });

    const succeeded = await read({ status: "succeeded", responseStatus: 200 });

    expect(succeeded).toMatchObject({ status: "completed", done: true });
    expect(succeeded?.result).toMatchObject({ id: "d1", responseStatus: 200 });
    expect(await read({ status: "dead", lastError: "HTTP 500" })).toMatchObject(
      {
        status: "failed",
        done: true,
        error: { message: "HTTP 500", hint: "WEBHOOK_DELIVERY_DEAD" },
      },
    );
    expect(await read({ status: "canceled" })).toMatchObject({
      status: "failed",
      error: { hint: "WEBHOOK_DELIVERY_CANCELED" },
    });
  });

  it("reports a delivery the caller cannot read as not found", async () => {
    const missing = await webhooks({ get_webhook_delivery: null }).jobs.get(
      "webhook:d9",
    );

    expect(!missing.ok && missing.error.kind).toBe("not_found");

    const unknown = await webhooks({
      get_webhook_delivery: delivery({ status: "paused" }),
    }).jobs.get("webhook:d1");

    expect(!unknown.ok && unknown.error.kind).toBe("not_found");
  });
});
