import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/index.ts";

const schemaOf = (layout = {}): string =>
  renderBlocks(["memberships", "tags"], layout)
    .filter((file) => file.kind === "schema" && file.module === "tags")
    .map((file) => file.contents)
    .join("\n");

describe("columns an app file adds to a block table", () => {
  const appColumns = {
    "better_supabase.tags": [
      { name: "region", type: "text not null default 'eu'" },
    ],
  };

  it("are fields of the block's functions, and the block adds none of them", () => {
    const plain = schemaOf();
    const withApp = schemaOf({ appColumns });

    expect(plain).not.toContain('"region"');
    expect(withApp).toContain('"region"');
    expect(withApp).toContain("'fields'");
    expect(withApp).not.toMatch(/add column[^;]*"region"/);
  });

  it("read the default from the app's own type text", () => {
    expect(schemaOf({ appColumns })).toContain("'eu'");
  });

  it("match the same columns an extraColumns option adds, without the add column", () => {
    const option = renderBlocks(["memberships", "tags"], {
      modules: {
        tags: {
          options: { extraColumns: { region: "text not null default 'eu'" } },
        },
      },
    })
      .filter((file) => file.kind === "schema" && file.module === "tags")
      .map((file) => file.contents)
      .join("\n");

    const strip = (sql: string): string =>
      sql
        .split("\n")
        .filter((line) => !/add column[^;]*"region"/.test(line))
        .join("\n")
        .replaceAll(/@bsb-hash.*\n/g, "");

    expect(strip(schemaOf({ appColumns }))).toBe(strip(option));
  });

  it("are ignored on a table the app creates", () => {
    expect(
      schemaOf({
        appColumns,
        ownTables: { "better_supabase.tags": "supabase/schemas/tags.sql" },
      }),
    ).not.toContain('"region"');
  });
});
