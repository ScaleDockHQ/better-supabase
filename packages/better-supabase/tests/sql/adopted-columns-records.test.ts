import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { adoptedColumnProblems } from "../../src/cli/adopted-columns.ts";
import { modulePermissionKeys } from "../../src/sql/introspect.ts";
import { adoptedTablesOf } from "../helpers/facts.ts";

const SUBJECTS = { product: { table: "public.products", idType: "uuid" } };

const MODULES: AnyBlocksConfig = {
  tags: {
    on: {
      product: {
        links: {
          table: "public.product_tags",
          subject: "product_id",
          tag: "tag_id",
          tenant: "organization_id",
        },
      },
    },
  },
};

const FILES = [
  {
    text: `create table public.product_tags (
  product_id uuid not null,
  tag_id uuid not null,
  organization_id uuid not null
);`,
  },
];

describe("blocks.<name>.on entries that inherit from config.recordTypes", () => {
  it("takes the table and id type of a registered record", async () => {
    const tables = await adoptedTablesOf(MODULES, undefined, {
      subjects: SUBJECTS,
    });

    expect(
      tables.some(
        (table) => table.module === "tags" && table.table === "product_tags",
      ),
    ).toBe(true);
    expect(
      await adoptedColumnProblems(
        MODULES,
        FILES,
        ["public"],
        undefined,
        SUBJECTS,
      ),
    ).toEqual([]);
    expect(
      modulePermissionKeys(MODULES, ["tags"], SUBJECTS).map(
        (entry) => entry.action,
      ),
    ).toContain("apply");
  });

  it("still needs a table for a type config.recordTypes doesn't register", async () => {
    await expect(adoptedTablesOf(MODULES)).rejects.toThrow(/needs a table/u);
  });
});
