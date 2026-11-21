import { describe, expect, it } from "vitest";

import type { Memory } from "../../../src/blocks/memory/index.ts";

import { importMemories } from "../../../src/blocks/memory/import.ts";
import { ok } from "../../../src/core/result.ts";

type Upsert = Parameters<Memory["archival"]["upsert"]>[0];

function fixture(rows: readonly Record<string, unknown>[]) {
  const saved: Upsert[] = [];
  const queries: { text: string; params: unknown[] | undefined }[] = [];

  // SAFETY: the import only calls archival.upsert.
  const memory = {
    archival: {
      upsert: (input: Upsert) => {
        saved.push(input);

        return Promise.resolve(ok({}));
      },
    },
  } as unknown as Memory;

  const source = {
    queryRaw: (text: string, params?: unknown[]) => {
      queries.push({ text, params });
      const after = params?.[0];

      return Promise.resolve(
        rows.filter(
          (row) => typeof after !== "string" || String(row["id"]) > after,
        ),
      );
    },
  } as never;

  return { memory, queries, saved, source };
}

describe("importMemories", () => {
  it("copies rows with their embeddings and returns the cursor", async () => {
    const { memory, queries, saved, source } = fixture([
      { id: "1", content: "likes tea", embedding: "[1,2]", category: "diet" },
      { id: "2", content: "  ", embedding: null },
      { id: "3", content: "lives in Delft", embedding: null },
    ]);

    const result = await importMemories({
      memory,
      source,
      table: "legacy.agent_memories",
      organizationId: null,
      embeddingModel: "old-model",
      columns: { category: "category" },
    });

    expect(result.data).toEqual({ imported: 2, skipped: 1, lastId: "3" });
    expect(queries[0]?.text).toContain('from "legacy"."agent_memories"');
    expect(saved[0]).toMatchObject({
      content: "likes tea",
      embedding: "[1,2]",
      embeddingModel: "old-model",
      category: "diet",
      sourceMessageId: "import:legacy.agent_memories:1",
    });
    expect(saved[1]).not.toHaveProperty("embedding");
  });

  it("continues after a cursor and honors the limit", async () => {
    const { memory, queries, source } = fixture([
      { id: "1", content: "a" },
      { id: "2", content: "b" },
    ]);

    await importMemories({
      memory,
      source,
      table: "memories",
      organizationId: null,
      after: "1",
      limit: 1,
    });

    expect(queries[0]?.params).toEqual(["1"]);
    expect(queries[0]?.text).toContain("limit 1");
  });

  it("rejects table and column names that are not plain identifiers", async () => {
    const { memory, source } = fixture([]);

    const result = await importMemories({
      memory,
      source,
      table: 'memories"; drop table x; --',
      organizationId: null,
    });

    expect(result.ok).toBe(false);
  });
});
