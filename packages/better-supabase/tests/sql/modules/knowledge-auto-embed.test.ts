import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const BLOCKS = [
  "memberships",
  "organizations",
  "permissions",
  "vector-search",
  "knowledge",
];

const sqlOf = (options?: Record<string, unknown>): string =>
  renderBlocks(BLOCKS, {
    ...(options === undefined ? {} : { modules: { knowledge: { options } } }),
  })
    .filter((file) => file.module === "knowledge")
    .map((file) => file.contents)
    .join("\n");

describe("knowledge autoEmbed", () => {
  it("adds the drain and the cron job when on", () => {
    const sql = sqlOf({ autoEmbed: true });

    expect(sql).toContain("process_knowledge_embeddings");
    expect(sql).toContain("embedding_worker_url");
    expect(sql).toContain("cron.schedule('knowledge_embeddings'");
  });

  it("adds nothing by default", () => {
    expect(sqlOf()).not.toContain("process_knowledge_embeddings");
  });
});
