import Ajv2020 from "ajv/dist/2020.js";
import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { designSchema } from "../../src/preset/index.ts";
import { DESIGN_SCHEMA, renderDesignSchema } from "./design-json-schema.ts";

const VALID: readonly unknown[] = [
  {},
  { version: 5 },
  {
    appTables: {
      projects: {
        columns: {
          name: { type: "text", nullable: false },
          budget_minor: { type: "bigint", default: "0" },
        },
        unique: [["name"]],
      },
    },
    extraColumns: { tags: { color: "text not null default 'gray'" } },
    positions: { "app.projects": [10, 20] },
  },
];

const INVALID: readonly unknown[] = [
  [],
  "design",
  { tables: {} },
  { version: -1 },
  { version: 1.5 },
  { positions: { "app.projects": [1] } },
  { positions: { "app.projects": [1, "2"] } },
  { extraColumns: { tags: { color: 1 } } },
  { appTables: { projects: { columns: { name: { type: "money" } } } } },
  { appTables: { projects: { columns: { name: { kind: "text" } } } } },
];

describe("schemas/design-v1.json", () => {
  it("is rendered from the design schema", async () => {
    // Compared as JSON: Oxfmt formats the file after the script writes it.
    expect(JSON.parse(await readFile(DESIGN_SCHEMA, "utf-8"))).toEqual(
      JSON.parse(renderDesignSchema()),
    );
  });

  const ajv = new Ajv2020({ strict: true });

  const fits = async (value: unknown): Promise<readonly boolean[]> => {
    const validate = ajv.compile(
      JSON.parse(await readFile(DESIGN_SCHEMA, "utf-8")),
    );

    const standard = await designSchema["~standard"].validate(value);

    ajv.removeSchema();

    return [validate(value), standard.issues === undefined];
  };

  it.each(VALID.map((design) => [JSON.stringify(design), design]))(
    "and designSchema both accept %s",
    async (_, design) => {
      expect(await fits(design)).toEqual([true, true]);
    },
  );

  it.each(INVALID.map((design) => [JSON.stringify(design), design]))(
    "and designSchema both reject %s",
    async (_, design) => {
      expect(await fits(design)).toEqual([false, false]);
    },
  );
});

describe("designSchema", () => {
  it("returns the design without its empty parts", async () => {
    expect(
      await designSchema["~standard"].validate({ appTables: {}, version: 0 }),
    ).toEqual({ value: {} });
  });

  it("lists the keys of the issue's JSON Pointer as its path", async () => {
    expect(
      await designSchema["~standard"].validate({
        positions: { "a/b": [1, 2] },
      }),
    ).toEqual({
      issues: [
        {
          message: 'design.positions: "a/b" is not a schema.table name',
          path: ["positions", "a/b"],
        },
      ],
    });
  });
});
