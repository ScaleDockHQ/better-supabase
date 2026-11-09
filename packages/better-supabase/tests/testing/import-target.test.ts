import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { testImportTarget } from "../../src/testing/import-target.ts";

const ENTITIES = /when '([a-z0-9_]+)' then/gu;

describe("import target tests", () => {
  it("covers every built-in target", () => {
    const sql = renderBlocks([
      "imports",
      "invoices",
      "quotes",
      "orders",
      "catalog",
      "inventory",
    ])
      .map((file) => file.contents)
      .join("\n");

    const entities = [
      ...new Set([...sql.matchAll(ENTITIES)].map((match) => match[1]!)),
    ];

    expect(entities.length).toBeGreaterThan(5);

    for (const entity of entities) {
      const text = testImportTarget({
        entity,
        fixture: { key: `${entity}-1`, data: { name: entity } },
      });

      expect(text).toContain(`'${entity}: first import inserts'`);
      expect(text).toContain("the target returns updatedAt");
    }
  });
});
