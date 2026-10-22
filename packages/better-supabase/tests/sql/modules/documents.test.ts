import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { documents: { options } },
});

describe("documents module", () => {
  it("keeps an update log and a snapshot per document", () => {
    const sql = sqlOf(["documents"], "documents");
    expect(sql).toContain(
      `create table if not exists "better_supabase"."documents"`,
    );
    expect(sql).toContain(
      `create table if not exists "better_supabase"."document_updates"`,
    );
    expect(sql).toContain(
      `create table if not exists "better_supabase"."document_snapshots"`,
    );
    expect(sql).toContain("DOCUMENT_UPDATE_TOO_LARGE");
    expect(sql).toContain("if length(v_bytes) > 1048576 then");
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."document_updates_after"(uuid, bigint) from public, anon, authenticated;`,
    );
  });

  it("guards the private topic with the document's read and write rules", () => {
    const sql = sqlOf(["documents"], "documents");
    expect(sql).toContain("like 'documents:%'");
    expect(sql).toContain(
      `"better_supabase"."document_topic_access"((select realtime.topic()), true)`,
    );
    expect(sql).toContain("realtime.messages.extension = 'presence'");
  });

  it("takes the topic prefix and limits from options", () => {
    const sql = sqlOf(
      ["documents"],
      "documents",
      withOptions({ topic: "docs", maxUpdateBytes: 2048, compactAfter: 10 }),
    );

    expect(sql).toContain("like 'docs:%'");
    expect(sql).toContain("if length(v_bytes) > 2048 then");
    expect(sql).toContain("if v_since = 10 then");
    expect(() =>
      sqlOf(["documents"], "documents", withOptions({ topic: "Docs!" })),
    ).toThrow(/options\.topic/);
    expect(() =>
      sqlOf(["documents"], "documents", withOptions({ compactAfter: 0 })),
    ).toThrow(/compactAfter/);
  });

  it("enqueues compaction with the queue block", () => {
    expect(sqlOf(["documents"], "documents")).not.toContain("enqueue_job");
    expect(sqlOf(["documents", "queue"], "documents")).toContain(
      `queue => 'documents.compact'`,
    );
  });

  it("saves states as versions when the versions module is installed", () => {
    expect(sqlOf(["documents"], "documents")).not.toContain(
      "save_document_version",
    );
    const sql = sqlOf(["documents", "versions"], "documents");
    expect(sql).toContain(`"better_supabase"."version_insert"(`);
    expect(sql).toContain("list_document_versions");
    expect(sql).toContain("get_document_version");
  });

  it("renders nothing in custom mode", () => {
    expect(
      sqlOf(["documents"], "documents", {
        modules: { documents: { mode: "custom" } },
      }).trim(),
    ).toBe("");
  });
});
