import type { ToolExecutionOptions } from "ai";

import { embed, embedMany, wrapEmbeddingModel } from "ai";
import { MockEmbeddingModelV4, MockRerankingModelV4 } from "ai/test";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { AiCache } from "../../../src/blocks/ai-cache/index.ts";
import type {
  Knowledge,
  KnowledgeHit,
} from "../../../src/blocks/knowledge/index.ts";

import {
  embeddingCacheMiddleware,
  embedWith,
  modelName,
  rerankHits,
  rerankWith,
  searchTool,
  supabaseEmbed,
  toSourceParts,
} from "../../../src/ai-sdk/embeddings/index.ts";
import { DbException, dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

const hit = (documentId: string, index: number, score = 1): KnowledgeHit => ({
  documentId,
  index,
  content: `${documentId} chunk ${String(index)}`,
  metadata: {},
  title: `Doc ${documentId}`,
  score,
  chunkId: `${documentId}#${String(index)}`,
  organizationId: undefined,
});

const call: ToolExecutionOptions<unknown> = {
  context: {},
  toolCallId: "c1",
  messages: [],
  abortSignal: new AbortController().signal,
};

function fakeKnowledge(hits: readonly KnowledgeHit[] | "fail") {
  const search = vi.fn(() =>
    AsyncResult.from(async () =>
      hits === "fail" ? err(dbError("forbidden", "nope")) : ok(hits),
    ),
  );

  // SAFETY: the tool calls only `search`.
  return { knowledge: { search } as unknown as Knowledge, search };
}

describe("embedWith", () => {
  it("embeds through embedMany and names the model", async () => {
    const model = new MockEmbeddingModelV4({
      provider: "openai",
      modelId: "text-embedding-3-small",
      maxEmbeddingsPerCall: 10,
      doEmbed: async ({ values }) => ({
        embeddings: values.map((value) => [value.length, 0]),
        warnings: [],
      }),
    });

    const embedder = embedWith(model, { providerOptions: { openai: {} } });
    expect(embedder.model).toBe("openai/text-embedding-3-small");
    const signal = new AbortController().signal;
    expect(embedder.apiVersion).toBe(2);
    expect(
      (await embedder.embed(["ab", "abc"], { signal })).embeddings,
    ).toEqual([
      [2, 0],
      [3, 0],
    ]);
    expect((await embedder.embed([])).embeddings).toEqual([]);
    expect(model.doEmbedCalls).toHaveLength(1);
    expect(embedWith(model, { name: "custom" }).model).toBe("custom");
    expect(modelName("openai/text-embedding-3-large")).toBe(
      "openai/text-embedding-3-large",
    );
  });
});

describe("rerankWith", () => {
  it("reorders hits by the model's ranking and keeps topN", async () => {
    const model = new MockRerankingModelV4({
      doRerank: async () => ({
        ranking: [
          { index: 2, relevanceScore: 0.9 },
          { index: 0, relevanceScore: 0.4 },
        ],
      }),
    });

    const hits = [hit("a", 0), hit("b", 0), hit("c", 0)];

    const reranked = await rerankWith(model, { topN: 3 })("q", hits, {
      signal: new AbortController().signal,
    });

    expect(reranked.map((item) => [item.documentId, item.score])).toEqual([
      ["c", 0.9],
      ["a", 0.4],
    ]);
    const one = [hit("a", 0)];
    expect(await rerankWith(model)("q", one)).toBe(one);
  });
});

describe("searchTool model output", () => {
  it("is strict and can send the model only ids and trimmed text", async () => {
    const { knowledge } = fakeKnowledge([hit("a", 0)]);
    const plain = searchTool(knowledge, "org");

    const trimmed = searchTool(knowledge, "org", {
      modelOutput: { maxCharacters: 3 },
    });

    expect(plain.strict).toBe(true);
    expect(plain.toModelOutput).toBeUndefined();

    const output = await trimmed.execute?.({ query: "q" }, call);

    const modelOutput = await trimmed.toModelOutput?.({
      toolCallId: "c",
      input: { query: "q" },
      // SAFETY: the tool's own result, which `execute` returned.
      output: output as never,
    });

    expect(modelOutput).toEqual({
      type: "json",
      value: { results: [{ id: "a#0", content: "a c" }] },
    });
  });
});

describe("searchTool", () => {
  it("searches as the caller and returns citable ids", async () => {
    const { knowledge, search } = fakeKnowledge([hit("a", 1), hit("b", 0)]);
    const onHits = vi.fn();
    const searchKnowledge = searchTool(knowledge, "org", { k: 3, onHits });
    expect(searchKnowledge.description).toContain("knowledge base");
    const output = await searchKnowledge.execute?.({ query: "refunds" }, call);
    expect(output).toEqual({
      results: [
        { id: "a#1", title: "Doc a", content: "a chunk 1" },
        { id: "b#0", title: "Doc b", content: "b chunk 0" },
      ],
    });
    expect(search).toHaveBeenCalledWith({
      organizationId: "org",
      query: "refunds",
      k: 3,
      signal: call.abortSignal,
    });
    expect(onHits).toHaveBeenCalledOnce();
  });

  it("reranks the hits and surfaces a search error", async () => {
    const { knowledge } = fakeKnowledge([hit("a", 0), hit("b", 0)]);

    const reverse = vi.fn(
      async (_query: string, hits: readonly KnowledgeHit[]) =>
        hits.toReversed(),
    );

    const reranked = searchTool(knowledge, "org", {
      rerank: reverse,
      description: "Search the handbook",
    });

    expect(reranked.description).toBe("Search the handbook");

    const output = await reranked.execute?.(
      { query: "q" },
      { toolCallId: "c2", messages: [], context: {} },
    );

    expect(output).toMatchObject({ results: [{ id: "b#0" }, { id: "a#0" }] });
    expect(reverse).toHaveBeenCalledWith("q", expect.any(Array), {
      organizationId: "org",
    });

    const { knowledge: failing } = fakeKnowledge("fail");
    await expect(
      searchTool(failing, "org").execute?.(
        { query: "q" },
        { toolCallId: "c3", messages: [], context: {} },
      ),
    ).rejects.toSatisfy(
      (error) => error instanceof DbException && error.message === "nope",
    );
  });

  it("drops the hits the results filter removes before rerank and onHits", async () => {
    const { knowledge } = fakeKnowledge([hit("a", 0), hit("secret", 0)]);
    const onHits = vi.fn();

    const rerank = vi.fn(
      async (_query: string, hits: readonly KnowledgeHit[]) => hits,
    );

    const results = vi.fn(async (hits: readonly KnowledgeHit[]) =>
      hits.filter((item) => item.documentId !== "secret"),
    );

    const output = await searchTool(knowledge, "org", {
      results,
      rerank,
      onHits,
    }).execute?.({ query: "q" }, call);

    expect(output).toEqual({
      results: [{ id: "a#0", title: "Doc a", content: "a chunk 0" }],
    });
    expect(results).toHaveBeenCalledWith(expect.any(Array), { query: "q" });
    expect(rerank.mock.calls[0]?.[1]).toHaveLength(1);
    expect(onHits).toHaveBeenCalledWith([hit("a", 0)]);
  });
});

describe("toSourceParts", () => {
  it("gives one source part per document", () => {
    expect(toSourceParts([hit("a", 0), hit("a", 1), hit("b", 2)])).toEqual([
      {
        type: "source-document",
        sourceId: "a#0",
        mediaType: "text/plain",
        title: "Doc a",
      },
      {
        type: "source-document",
        sourceId: "b#2",
        mediaType: "text/plain",
        title: "Doc b",
      },
    ]);
  });
});

describe("supabaseEmbed", () => {
  afterEach(() => {
    Reflect.deleteProperty(globalThis, "Supabase");
  });

  it("runs Supabase.ai.Session with mean pooling", async () => {
    const run = vi.fn(async (input: string) => [input.length, 0.5]);
    const models: string[] = [];
    Reflect.set(globalThis, "Supabase", {
      ai: {
        Session: class {
          constructor(model: string) {
            models.push(model);
          }
          run = run;
        },
      },
    });
    const embedder = supabaseEmbed();
    expect(embedder.model).toBe("supabase/gte-small");
    expect(await embedder.embed(["abc", "de"])).toEqual([
      [3, 0.5],
      [2, 0.5],
    ]);
    await embedder.embed(["x"]);
    expect(models).toEqual(["gte-small"]);
    expect(run).toHaveBeenCalledWith("abc", {
      mean_pool: true,
      normalize: true,
    });
  });

  it("fails outside Edge Functions and on a non-vector output", async () => {
    await expect(supabaseEmbed().embed(["a"])).rejects.toThrow(
      "Supabase Edge Functions",
    );
    const session = { run: async () => "nope" };
    await expect(
      supabaseEmbed({ model: "other", session }).embed(["a"]),
    ).rejects.toThrow("no vector for other");
  });
});

describe("embedWith dimensions and single values", () => {
  it("passes dimensions and takes the single-value path", async () => {
    const seen: { values: string[]; dimensions: number | undefined }[] = [];

    const model = new MockEmbeddingModelV4({
      maxEmbeddingsPerCall: 10,
      doEmbed: async ({ values, dimensions }) => {
        seen.push({ values, dimensions });

        return {
          embeddings: values.map(() => [1, 2]),
          usage: { tokens: values.length },
          warnings: [],
        };
      },
    });

    const embedder = embedWith(model, { dimensions: 2 });
    const one = await embedder.embed(["a"]);
    expect(one.embeddings).toEqual([[1, 2]]);
    await embedder.embed(["a", "b"]);
    expect(seen).toEqual([
      { values: ["a"], dimensions: 2 },
      { values: ["a", "b"], dimensions: 2 },
    ]);
  });
});

function embedCache() {
  const entries = new Map<string, unknown>();
  const keys: string[] = [];

  const cache: Pick<AiCache, "get" | "upsert"> = {
    get: (key) =>
      AsyncResult.ok(
        entries.has(key)
          ? {
              key,
              organizationId: undefined,
              kind: "embed",
              model: undefined,
              // SAFETY: the test reads back what it stored.
              value: entries.get(key) as never,
              hits: 1,
              createdAt: Temporal.Now.instant(),
              lastHitAt: undefined,
              expiresAt: Temporal.Now.instant(),
            }
          : undefined,
      ),
    upsert: ({ key, value }) => {
      entries.set(key, value);
      keys.push(key);

      return AsyncResult.ok({
        key,
        organizationId: undefined,
        kind: "embed",
        model: undefined,
        hits: 0,
        createdAt: Temporal.Now.instant(),
        lastHitAt: undefined,
        expiresAt: Temporal.Now.instant(),
      });
    },
  };

  return { cache, keys };
}

describe("embeddingCacheMiddleware", () => {
  it("sends only uncached values to the model", async () => {
    const calls: string[][] = [];

    const base = new MockEmbeddingModelV4({
      maxEmbeddingsPerCall: 10,
      doEmbed: async ({ values }) => {
        calls.push(values);

        return {
          embeddings: values.map((value) => [value.length]),
          warnings: [],
        };
      },
    });

    const { cache, keys } = embedCache();

    const model = wrapEmbeddingModel({
      model: base,
      middleware: embeddingCacheMiddleware({ cache, ttl: 60 }),
    });

    const first = await embedMany({ model, values: ["a", "bb"] });
    expect(first.embeddings).toEqual([[1], [2]]);
    const second = await embedMany({ model, values: ["bb", "ccc", "a"] });
    expect(second.embeddings).toEqual([[2], [3], [1]]);
    expect(calls).toEqual([["a", "bb"], ["ccc"]]);
    expect(new Set(keys).size).toBe(3);

    const third = await embed({ model, value: "a" });
    expect(third.embedding).toEqual([1]);
    expect(calls).toHaveLength(2);
  });

  it("keeps entries apart by dimensions and tenant", async () => {
    const base = new MockEmbeddingModelV4({
      doEmbed: async ({ values }) => ({
        embeddings: values.map(() => [0]),
        warnings: [],
      }),
    });

    const { cache, keys } = embedCache();

    const wrap = (organizationId: string) =>
      wrapEmbeddingModel({
        model: base,
        middleware: embeddingCacheMiddleware({ cache, ttl: 1, organizationId }),
      });

    await embed({ model: wrap("o1"), value: "a" });
    await embed({ model: wrap("o2"), value: "a" });
    await embed({ model: wrap("o1"), value: "a", dimensions: 8 });
    expect(new Set(keys).size).toBe(3);
  });
});

describe("rerankHits", () => {
  it("reranks any hit shape", async () => {
    const model = new MockRerankingModelV4({
      doRerank: async () => ({
        ranking: [
          { index: 1, relevanceScore: 0.9 },
          { index: 0, relevanceScore: 0.1 },
        ],
      }),
    });

    const rerank = rerankHits<{ id: string; body: string }>(model, {
      text: (hit) => hit.body,
    });

    const hits = [
      { id: "a", body: "x" },
      { id: "b", body: "y" },
    ];

    expect((await rerank("q", hits)).map((hit) => hit.id)).toEqual(["b", "a"]);
    expect(await rerank("q", [hits[0] ?? { id: "", body: "" }])).toHaveLength(
      1,
    );
  });
});
