import { embed, generateText, rerank } from "ai";
import {
  MockEmbeddingModelV4,
  MockLanguageModelV4,
  MockRerankingModelV4,
} from "ai/test";
import { describe, expect, it } from "vitest";

import type { Usage, UsageEntry } from "../../src/blocks/usage/usage.ts";
import type { DbError } from "../../src/core/errors.ts";

import {
  gatewayOptions,
  meterTelemetry,
  spendReconciliation,
  tenantOfEvent,
} from "../../src/ai-sdk/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

const job = undefined as never;
const signal = new AbortController().signal;

function fakeUsage(fail = false) {
  const rows: {
    organizationId: string;
    entries: readonly UsageEntry[];
    options: unknown;
  }[] = [];
  const usage: Pick<Usage, "recordMany"> = {
    recordMany: (organizationId, entries, options) => {
      if (fail) return AsyncResult.err(dbError("network", "down"));
      rows.push({ organizationId, entries, options });
      return AsyncResult.ok({ recorded: entries.length } as never);
    },
  };
  return { usage, rows };
}

const languageModel = () =>
  new MockLanguageModelV4({
    doGenerate: async () => ({
      content: [{ type: "text", text: "Hi" }],
      finishReason: { unified: "stop", raw: "stop" },
      usage: {
        inputTokens: { total: 12, noCache: 12, cacheRead: 0, cacheWrite: 0 },
        outputTokens: { total: 3, text: 3, reasoning: 0 },
      },
      warnings: [],
    }),
  });

describe("tenantOfEvent", () => {
  const base = { callId: "c", operationId: "ai.generateText" };
  it("reads the org tag, then the runtime context", () => {
    expect(
      tenantOfEvent({
        ...base,
        providerOptions: { gateway: { tags: ["chat:1", "org:o1"] } },
        runtimeContext: { organizationId: "o2" },
      }),
    ).toBe("o1");
    expect(
      tenantOfEvent({ ...base, runtimeContext: { organizationId: "o2" } }),
    ).toBe("o2");
    expect(
      tenantOfEvent({
        ...base,
        providerOptions: { gateway: { tags: ["org:"] } },
      }),
    ).toBeUndefined();
    expect(tenantOfEvent(base)).toBeUndefined();
  });
});

describe("meterTelemetry", () => {
  it("meters a language model call on the tenant from the gateway tags", async () => {
    const { usage, rows } = fakeUsage();
    await generateText({
      model: languageModel(),
      prompt: "Hi",
      providerOptions: gatewayOptions({ organizationId: "o1" }),
      telemetry: { integrations: meterTelemetry({ usage }) },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0]?.organizationId).toBe("o1");
    expect(rows[0]?.entries).toEqual([
      { meter: "ai.input_tokens", quantity: 12 },
      { meter: "ai.output_tokens", quantity: 3 },
    ]);
    expect(rows[0]?.options).toMatchObject({
      source: "ai:telemetry",
      idempotencyKey: expect.stringMatching(/^ai-call:.+:0$/),
    });
  });

  it("meters embeddings and reranks on custom meters", async () => {
    const { usage, rows } = fakeUsage();
    const telemetry = {
      integrations: meterTelemetry({
        usage,
        tenant: () => "o1",
        meters: { embedding: "emb", rerank: "rr" },
        source: "test",
      }),
    };
    await embed({
      model: new MockEmbeddingModelV4({
        doEmbed: async () => ({
          embeddings: [[1, 0]],
          usage: { tokens: 4 },
          warnings: [],
        }),
      }),
      value: "a",
      telemetry,
    });
    await rerank({
      model: new MockRerankingModelV4({
        doRerank: async () => ({
          ranking: [{ index: 0, relevanceScore: 1 }],
          warnings: [],
        }),
      }),
      documents: ["a"],
      query: "a",
      telemetry,
    });
    expect(rows.map((row) => row.entries)).toEqual([
      [{ meter: "emb", quantity: 4 }],
      [{ meter: "rr", quantity: 1 }],
    ]);
  });

  it("skips calls without a tenant and reports write errors", async () => {
    const quiet = fakeUsage();
    await generateText({
      model: languageModel(),
      prompt: "Hi",
      telemetry: { integrations: meterTelemetry({ usage: quiet.usage }) },
    });
    expect(quiet.rows).toEqual([]);
    const errors: DbError[] = [];
    await generateText({
      model: languageModel(),
      prompt: "Hi",
      telemetry: {
        integrations: meterTelemetry({
          usage: fakeUsage(true).usage,
          tenant: () => "o1",
          onError: (error) => errors.push(error),
        }),
      },
    });
    expect(errors).toHaveLength(1);
  });
});

describe("spendReconciliation", () => {
  it("records yesterday's spend per tenant once", async () => {
    const { usage, rows } = fakeUsage();
    const params: unknown[] = [];
    const handler = spendReconciliation({
      usage,
      credentialType: "system",
      now: () => Temporal.Instant.from("2026-03-02T01:00:00Z"),
      gateway: {
        getSpendReport: async (input) => {
          params.push(input);
          return {
            results: [
              { tag: "org:o1", totalCost: 0.0123456, requestCount: 4 },
              { tag: "org:o2", totalCost: 0 },
              { tag: "chat:1", totalCost: 5 },
              { totalCost: 1 },
            ],
          };
        },
      },
    });
    const report = await handler(undefined, job, signal);
    expect(params).toEqual([
      {
        startDate: "2026-03-01",
        endDate: "2026-03-01",
        groupBy: "tag",
        credentialType: "system",
      },
    ]);
    expect(report).toEqual({
      day: "2026-03-01",
      tenants: [
        { organizationId: "o1", costMicroUsd: 12346, requests: 4 },
        { organizationId: "o2", costMicroUsd: 0, requests: 0 },
      ],
    });
    expect(rows).toEqual([
      {
        organizationId: "o1",
        entries: [{ meter: "ai.gateway_cost", quantity: 12346 }],
        options: {
          idempotencyKey: "ai-spend:2026-03-01:o1",
          source: "ai:gateway-spend",
        },
      },
    ]);
    await spendReconciliation({
      usage,
      meter: "cost",
      gateway: { getSpendReport: async () => ({ results: [] }) },
    })({ day: "2026-01-01" }, job, signal);
  });
});
