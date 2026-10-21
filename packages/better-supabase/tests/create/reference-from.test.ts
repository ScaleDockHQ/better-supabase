import { describe, expect, test } from "vitest";

import {
  parseSchema,
  referenceFrom,
  schemaData,
} from "../../src/create/index.ts";

const preset = {
  scope: "user",
  tenantName: "organization",
  idType: "uuid",
} as const;

const data = schemaData(
  parseSchema([
    {
      path: "a.sql",
      module: "a",
      contents: `
        create table public.pairs (a int, b int, primary key (a, b));
        create table public.jsons (id jsonb primary key);
        create table public.counters (id serial primary key);
        create table public.codes (id int8 primary key);`,
    },
  ]),
);

const design = { appTables: { notes: { columns: {} } } };

describe("referenceFrom refusals", () => {
  test("names the problem", () => {
    expect(
      referenceFrom(design, data, preset, "x", "public.pairs"),
    ).toMatchObject({ ok: false, error: "x is not in the design." });
    expect(
      referenceFrom(design, data, preset, "notes", "public.nowhere"),
    ).toMatchObject({ ok: false, error: "That table is not in the schema." });
    expect(
      referenceFrom(design, data, preset, "notes", "public.pairs"),
    ).toMatchObject({ ok: false, error: expect.stringMatching(/single/u) });
    expect(
      referenceFrom(design, data, preset, "notes", "public.jsons"),
    ).toMatchObject({ ok: false });
  });

  test("a table that isn't an app or block table can't be referenced", () => {
    for (const id of ["public.counters", "public.codes"]) {
      expect(referenceFrom(design, data, preset, "notes", id)).toMatchObject({
        ok: false,
        error: expect.stringMatching(/can't be referenced/u),
      });
    }
  });
});
