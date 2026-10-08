import type { ToolExecutionOptions } from "ai";

import { MockEmbeddingModelV4, MockRerankingModelV4 } from "ai/test";
import { afterEach, describe, expect, it, vi } from "vitest";

import type {
  Knowledge,
  KnowledgeHit,
} from "../../../src/blocks/knowledge/index.ts";

import {
  embedWith,
  modelName,
  rerankWith,
  searchTool,
  supabaseEmbed,
  toSourceParts,
} from "../../../src/ai-sdk/embeddings/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

const hit = (documentId: string, index: number, score = 1): KnowledgeHit => ({
  documentId,
  index,
  content: `${documentId} chunk ${String(index)}`,
  metadata: {},
  title: `Doc ${documentId}`,
  score,
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
    expect(await embedder.embed(["ab", "abc"], { signal })).toEqual([
      [2, 0],
      [3, 0],
    ]);
    expect(await embedder.embed([])).toEqual([]);
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
    expect(search).toHaveBeenCalledWith("org", "refunds", {
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
    expect(output).toMatchObject({
      results: [{ id: "b#0" }, { id: "a#0" }],
    });
    expect(reverse).toHaveBeenCalledWith("q", expect.any(Array), undefined);

    const { knowledge: failing } = fakeKnowledge("fail");
    await expect(
      searchTool(failing, "org").execute?.(
        { query: "q" },
        { toolCallId: "c3", messages: [], context: {} },
      ),
    ).rejects.toThrow("nope");
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
