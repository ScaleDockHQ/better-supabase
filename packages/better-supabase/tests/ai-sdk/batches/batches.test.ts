import type { Experimental_BatchItemResult } from "ai";

import { describe, expect, it, vi } from "vitest";

import type {
  AiBatch,
  AiBatchItemInput,
  AiBatchPatch,
  AiProviders,
} from "../../../src/blocks/ai-providers/index.ts";

import { aiBatches, batchItemOf } from "../../../src/ai-sdk/batches/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const AT = Temporal.Instant.from("2026-01-01T00:00:00Z");
const REF = { version: 2 as const, id: "batch_1", provider: "openai" };
const USAGE = {
  inputTokens: 3,
  inputTokenDetails: {
    noCacheTokens: 3,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
  },
  outputTokens: 1,
  outputTokenDetails: { textTokens: 1, reasoningTokens: 0 },
  totalTokens: 4,
};

const batch = (over: Partial<AiBatch> = {}): AiBatch => ({
  id: "b1",
  organizationId: "o1",
  userId: "u1",
  provider: "openai",
  reference: REF,
  status: "pending",
  rawStatus: undefined,
  itemCount: 2,
  counts: {},
  error: undefined,
  metadata: {},
  resultsSaved: false,
  polls: 1,
  nextPollAt: AT,
  expiresAt: undefined,
  completedAt: undefined,
  createdAt: AT,
  updatedAt: AT,
  ...over,
});

const textItem = (id: string): Experimental_BatchItemResult =>
  ({
    type: "text",
    id,
    status: "succeeded",
    text: `answer ${id}`,
    content: [{ type: "text", text: `answer ${id}` }],
    finishReason: "stop",
    usage: USAGE,
  }) as never;

function fakeStore(due: AiBatch[] = []) {
  const updates: { id: string; patch: AiBatchPatch }[] = [];
  const saved: AiBatchItemInput[][] = [];
  const recorded: unknown[] = [];
  let current = batch();
  const store: AiProviders["batches"] = {
    record: (_org, input) => {
      recorded.push(input);
      return AsyncResult.ok(current);
    },
    get: () => AsyncResult.ok(current),
    list: () => AsyncResult.ok([current]),
    items: () => AsyncResult.ok([]),
    due: () => AsyncResult.ok(due),
    update: (id, patch) => {
      updates.push({ id, patch });
      current = {
        ...current,
        ...(patch.status === undefined ? {} : { status: patch.status }),
        ...(patch.resultsSaved === undefined
          ? {}
          : { resultsSaved: patch.resultsSaved }),
      };
      return AsyncResult.ok(current);
    },
    saveItems: (_id, items) => {
      saved.push([...items]);
      return AsyncResult.ok(items.length);
    },
  };
  return { store, updates, saved, recorded };
}

async function* results(count: number) {
  for (let index = 0; index < count; index++) yield textItem(`r${index}`);
}

describe("batchItemOf", () => {
  it("stores text, images and failures", () => {
    expect(batchItemOf(textItem("r1"))).toMatchObject({
      requestId: "r1",
      status: "succeeded",
      output: { text: "answer r1", finishReason: "stop" },
      usage: { totalTokens: 4 },
    });
    expect(
      batchItemOf({
        type: "image",
        id: "i1",
        status: "succeeded",
        images: [
          {
            mediaType: "image/png",
            base64: "AAA=",
            uint8Array: new Uint8Array(),
          },
        ],
      } as never),
    ).toEqual({
      requestId: "i1",
      status: "succeeded",
      output: { images: [{ mediaType: "image/png", base64: "AAA=" }] },
      usage: undefined,
    });
    expect(
      batchItemOf({
        type: "text",
        id: "r2",
        status: "failed",
        error: { message: "bad request" },
      } as never),
    ).toEqual({ requestId: "r2", status: "failed", error: "bad request" });
    expect(
      batchItemOf({ type: "text", id: "r3", status: "expired" } as never),
    ).toEqual({ requestId: "r3", status: "expired" });
  });
});

describe("aiBatches", () => {
  it("starts a batch and records it with its reference", async () => {
    const { store, recorded } = fakeStore();
    const start = vi.fn(async (_options: unknown) => ({
      ...REF,
      status: "pending" as const,
      rawStatus: "validating",
      requestCounts: { total: 2, pending: 2, completed: 0, failed: 0 },
      expiresAt: "2026-01-02T00:00:00Z",
      warnings: [],
    }));
    const batches = aiBatches({
      providers: { batches: store },
      api: { start },
    });
    await batches
      .start({ organizationId: "o1", userId: "u1" }, {
        requests: [
          { id: "a", model: "openai/gpt-5", prompt: "A" },
          { id: "b", model: "openai/gpt-5", prompt: "B" },
        ],
        metadata: { job: "nightly" },
      } as never)
      .orThrow();
    expect(start.mock.calls[0]?.[0]).not.toHaveProperty("metadata");
    expect(recorded[0]).toEqual({
      provider: "openai",
      reference: REF,
      itemCount: 2,
      status: "pending",
      userId: "u1",
      metadata: { job: "nightly" },
      rawStatus: "validating",
      counts: { total: 2, pending: 2, completed: 0, failed: 0 },
      expiresAt: Temporal.Instant.from("2026-01-02T00:00:00Z"),
    });
  });

  it("maps a provider failure to a network error", async () => {
    const { store } = fakeStore();
    const batches = aiBatches({
      providers: { batches: store },
      api: { start: () => Promise.reject(new Error("quota")) },
    });
    const started = await batches.start(
      { organizationId: "o1" },
      { requests: [] },
    );
    expect(!started.ok && started.error).toMatchObject({
      kind: "network",
      hint: "AI_BATCH_PROVIDER",
    });
  });

  it("polls a pending batch, then collects it in pages once it completes", async () => {
    const { store, updates, saved } = fakeStore([batch()]);
    const onDone = vi.fn();
    const provider = { id: "fake" } as never;
    const status = vi.fn(async (_options: unknown) => ({
      status: "completed" as const,
      rawStatus: "completed",
      requestCounts: { total: 150, pending: 0, completed: 150, failed: 0 },
      error: { message: "two expired" },
      expiresAt: "2026-01-03T00:00:00Z",
    }));
    const batches = aiBatches({
      providers: { batches: store },
      provider: () => provider,
      pollEvery: 30,
      onDone,
      api: { status, results: () => results(150) },
    });
    expect(
      await batches.pollJob()(
        undefined,
        undefined as never,
        new AbortController().signal,
      ),
    ).toBe(1);
    expect(status.mock.calls[0]?.[0]).toEqual({ provider, batch: REF });
    expect(updates[0]?.patch).toMatchObject({
      status: "completed",
      rawStatus: "completed",
      counts: { total: 150, pending: 0, completed: 150, failed: 0 },
      error: "two expired",
      expiresAt: Temporal.Instant.from("2026-01-03T00:00:00Z"),
    });
    expect(saved.map((page) => page.length)).toEqual([100, 50]);
    expect(updates[1]?.patch).toEqual({ resultsSaved: true, nextPollAt: null });
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it("leaves a pending batch for the next poll", async () => {
    const { store, saved } = fakeStore([batch()]);
    const batches = aiBatches({
      providers: { batches: store },
      api: { status: async () => ({ status: "pending" as const }) },
    });
    expect(await batches.poll().orThrow()).toBe(1);
    expect(saved).toEqual([]);
  });

  it("collects a finished batch whose results were not saved, with onItem", async () => {
    const { store, saved } = fakeStore([batch({ status: "completed" })]);
    const batches = aiBatches({
      providers: { batches: store },
      provider: { id: "fixed" } as never,
      onItem: (item) => ({
        requestId: item.id,
        status: "succeeded",
        output: "custom",
      }),
      api: { results: () => results(1) },
    });
    await batches.poll().orThrow();
    expect(saved).toEqual([
      [{ requestId: "r0", status: "succeeded", output: "custom" }],
    ]);
  });

  it("notes a poll error on the batch and keeps polling the rest", async () => {
    const { store, updates } = fakeStore([
      batch({ reference: {} }),
      batch({ id: "b2" }),
    ]);
    const batches = aiBatches({
      providers: { batches: store },
      api: {
        status: () => Promise.reject(new Error("timeout")),
      },
    });
    expect(await batches.poll().orThrow()).toBe(2);
    expect(updates.map((update) => [update.id, update.patch.error])).toEqual([
      ["b1", "batch b1 has no batch reference"],
      ["b2", "timeout"],
    ]);
  });

  it("stops a collect when results fail to stream or save", async () => {
    const { store } = fakeStore();
    const broken = aiBatches({
      providers: { batches: store },
      api: {
        // oxlint-disable-next-line require-yield -- the stream fails before its first item
        results: async function* () {
          throw new Error("gone");
        },
      },
    });
    expect((await broken.collect(batch())).ok).toBe(false);
    const failing = aiBatches({
      providers: {
        batches: {
          ...store,
          saveItems: () => AsyncResult.err(dbError("network", "down")),
        },
      },
      api: { results: () => results(150) },
    });
    expect((await failing.collect(batch())).ok).toBe(false);
    const tail = aiBatches({
      providers: {
        batches: {
          ...store,
          saveItems: () => AsyncResult.err(dbError("network", "down")),
        },
      },
      api: { results: () => results(1) },
    });
    expect((await tail.collect(batch())).ok).toBe(false);
  });

  it("reads stored state and cancels at the provider", async () => {
    const { store, updates } = fakeStore();
    const cancel = vi.fn(async () => undefined);
    const batches = aiBatches({
      providers: { batches: store },
      api: { cancel },
    });
    expect((await batches.status("b1").orThrow())?.id).toBe("b1");
    expect(await batches.results("b1", { limit: 10 }).orThrow()).toEqual([]);
    expect((await batches.cancel(batch()).orThrow()).status).toBe("cancelled");
    expect(cancel).toHaveBeenCalledWith({ batch: REF });
    expect(updates.at(-1)?.patch).toEqual({ status: "cancelled" });
  });
});
