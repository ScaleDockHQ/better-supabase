import { describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";

import { APP_TABLES_MODULE } from "../../src/sql/modules/app-tables.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const BLOCKS = ["memberships", "organizations", "updated-at"];

const sqlOf = (appTables: AppTablesConfig): string =>
  renderBlocks(BLOCKS, { appTables })
    .filter((file) => file.module === APP_TABLES_MODULE)
    .map((file) => file.contents)
    .join("\n");

describe("appTables embedding", () => {
  it("renders the embedding pipeline for the table", () => {
    const sql = sqlOf({
      articles: {
        columns: { title: { type: "text" }, body: { type: "text" } },
        embedding: { content: ["title", "body"], dimensions: 1536 },
      },
    });

    expect(sql).toContain(
      'alter table "public"."articles" add column if not exists "embedding" "extensions".halfvec(1536)',
    );
    expect(sql).toContain('"articles_apply_embedding"');
    expect(sql).toContain("pgmq.create('articles_embed')");
    expect(sql).toContain("concat_ws");
  });

  it("renders nothing without the option", () => {
    const sql = sqlOf({ articles: { columns: { title: { type: "text" } } } });

    expect(sql).not.toContain("apply_embedding");
  });
});
