import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

describe("codemod expire-tags", () => {
  it("names each tag call and its replacement and leaves the text", () => {
    const source = [
      'import { updateTag } from "next/cache";',
      "export async function save() {",
      '  updateTag("bsb:notes");',
      "}",
    ].join("\n");

    const result = applyCodemod(CODEMODS["expire-tags"]!, source);

    expect(result.text).toBe(source);
    expect(result.review).toHaveLength(1);
    expect(result.review[0]).toMatchObject({ line: 3 });
    expect(result.review[0]?.message).toContain(
      'await bsb.expireTags(["bsb:notes"])',
    );
  });
});
