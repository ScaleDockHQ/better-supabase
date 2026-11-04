import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const readMany = CODEMODS["read-many"]!;

describe("codemod read-many", () => {
  it("names a Promise.all of reads on one db and leaves the text", () => {
    const source = [
      "const [a, b] = await Promise.all([",
      "  db.customers.list(),",
      "  db.orders.count(),",
      "]);",
    ].join("\n");

    const result = applyCodemod(readMany, source);

    expect(result.text).toBe(source);
    expect(result.review).toHaveLength(1);
    expect(result.review[0]).toMatchObject({ line: 1 });
    expect(result.review[0]?.message).toContain("db.$many");
  });

  it("says when the group mixes in other calls", () => {
    const result = applyCodemod(
      readMany,
      "await Promise.all([db.customers.list(), fetch(url)]);",
    );

    expect(result.review[0]?.message).toContain("mixes");
  });

  it("ignores a single call", () => {
    expect(
      applyCodemod(readMany, "await Promise.all([db.customers.list()]);")
        .review,
    ).toEqual([]);
  });
});
