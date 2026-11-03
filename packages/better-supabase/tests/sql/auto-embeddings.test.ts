import { describe, expect, it } from "vitest";

import { renderAutoEmbedding } from "../../src/sql/auto-embeddings.ts";

describe("renderAutoEmbedding", () => {
  it("renders the column, index, triggers, drain and cron job", () => {
    const sql = renderAutoEmbedding({
      table: "articles",
      content: ["title", "body"],
      dimensions: 1536,
    });

    expect(sql).toContain(
      'add column if not exists "embedding" "extensions".halfvec(1536)',
    );
    expect(sql).toContain("using hnsw");
    expect(sql).toContain('"extensions".halfvec_cosine_ops');
    expect(sql).toContain("select pgmq.create('articles_embed')");
    expect(sql).toContain("cron.schedule('articles_embeddings', '10 seconds'");
    expect(sql).toContain("to_regprocedure('cron.schedule(text, text, text)')");
    expect(sql).toContain("vault.decrypted_secrets");
    expect(sql).toContain('"articles_apply_embedding"');
  });

  it("rejects bad names and sizes", () => {
    const base = { table: "a", content: ["t"], dimensions: 8 };

    expect(() => renderAutoEmbedding({ ...base, table: "a;drop" })).toThrow(
      /table/,
    );
    expect(() => renderAutoEmbedding({ ...base, content: [] })).toThrow(
      /content/,
    );
    expect(() =>
      renderAutoEmbedding({ ...base, dimensions: 2001, type: "vector" }),
    ).toThrow(/dimensions/);
    expect(() => renderAutoEmbedding({ ...base, schedule: "x'; --" })).toThrow(
      /schedule/,
    );
  });
});
