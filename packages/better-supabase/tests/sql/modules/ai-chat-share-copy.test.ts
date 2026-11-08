import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/index.ts";

const files = renderBlocks(["share-links", "ai-chat"]);

const of = (kind: "schema" | "data", module: string): string =>
  files.find((file) => file.kind === kind && file.module === module)
    ?.contents ?? "";

describe("the ai-chat share copy", () => {
  it("copies the old shares in the data file, not in a do block", () => {
    const data = of("data", "share-links");

    expect(data).toContain('from "better_supabase".ai_chat_shares s');
    expect(data).toContain("on conflict");
    expect(of("schema", "share-links")).not.toContain("ai_chat_shares s");
    expect(of("schema", "share-links")).not.toMatch(/^do \$\$/m);
  });

  it("writes no copy without a chats table of ai-chat's own", () => {
    expect(
      renderBlocks(["share-links"])
        .filter((file) => file.kind === "data")
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("ai_chat_shares");
  });
});
