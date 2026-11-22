import { beforeEach, describe, expect, it, vi } from "vitest";

import type * as OptionalPeer from "../../../src/core/optional-peer.ts";

const importPeer = vi.fn<(specifier: string) => Promise<unknown>>();

vi.mock(
  import("../../../src/core/optional-peer.ts"),
  async (importOriginal) => ({
    ...(await importOriginal<typeof OptionalPeer>()),
    importOptionalPeer: importPeer,
  }),
);

const {
  chainDelay,
  loadVercelQueue,
  retentionFor,
  retryAfterSeconds,
  vercelIdempotencyKey,
  vercelTopicOf,
  VERCEL_MAX_DELAY_SECONDS,
} = await import("../../../src/workflow-sdk/world/vercel-queue.ts");

describe("vercelTopicOf", () => {
  it("keeps workflow queue names and replaces characters Vercel rejects", () => {
    expect(vercelTopicOf("__wkf_workflow_orders")).toBe(
      "__wkf_workflow_orders",
    );
    expect(vercelTopicOf("__wkf_step_a.b:c/d")).toBe("__wkf_step_a-b-c-d");
  });
});

describe("chainDelay", () => {
  it("sends a delay of up to 23 hours in one hop", () => {
    expect(chainDelay(0)).toEqual({ delaySeconds: 0, remaining: 0 });
    expect(chainDelay(30.2)).toEqual({ delaySeconds: 31, remaining: 0 });
    expect(chainDelay(VERCEL_MAX_DELAY_SECONDS)).toEqual({
      delaySeconds: VERCEL_MAX_DELAY_SECONDS,
      remaining: 0,
    });
  });

  it("splits a longer delay into the first hop and what remains", () => {
    expect(chainDelay(VERCEL_MAX_DELAY_SECONDS + 7200)).toEqual({
      delaySeconds: VERCEL_MAX_DELAY_SECONDS,
      remaining: 7200,
    });
    expect(chainDelay(-5)).toEqual({ delaySeconds: 0, remaining: 0 });
  });
});

describe("retentionFor and retryAfterSeconds", () => {
  it("keeps a delayed message for its delay plus an hour, at most 7 days", () => {
    expect(retentionFor(0)).toBeUndefined();
    expect(retentionFor(60)).toBe(86_400);
    expect(retentionFor(VERCEL_MAX_DELAY_SECONDS)).toBe(
      VERCEL_MAX_DELAY_SECONDS + 3600,
    );
    expect(retentionFor(10 * 86_400)).toBe(7 * 86_400);
  });

  it("clamps the retry delay to the 5 to 900 second range Vercel accepts", () => {
    expect(retryAfterSeconds(1)).toBe(5);
    expect(retryAfterSeconds(120.2)).toBe(121);
    expect(retryAfterSeconds(22_026)).toBe(900);
  });
});

describe("vercelIdempotencyKey", () => {
  it("hashes keys longer than 256 characters", async () => {
    expect(await vercelIdempotencyKey("short")).toBe("short");

    const long = await vercelIdempotencyKey("k".repeat(300));
    expect(long).toMatch(/^[0-9a-f]{64}$/);
    expect(await vercelIdempotencyKey("k".repeat(300))).toBe(long);
  });
});

describe("loadVercelQueue", () => {
  beforeEach(() => {
    importPeer.mockReset();
  });

  it("builds a QueueClient from the installed package", async () => {
    class QueueClient {
      send = vi.fn();
      handleCallback = vi.fn();
    }

    importPeer.mockResolvedValue({ QueueClient });

    expect(await loadVercelQueue()).toBeInstanceOf(QueueClient);
    expect(importPeer).toHaveBeenCalledWith("@vercel/queue");
  });

  it("says how to install the peer when it is missing or too old", async () => {
    importPeer.mockResolvedValue(undefined);
    await expect(loadVercelQueue()).rejects.toThrow("@vercel/queue");

    importPeer.mockResolvedValue({ QueueClient: function QueueClient() {} });
    await expect(loadVercelQueue()).rejects.toThrow("@vercel/queue");
  });
});
