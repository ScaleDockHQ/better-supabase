import { describe, expect, it } from "vitest";

import {
  extraColumnDefault,
  insertExtraColumns,
} from "../../src/sql/shared.ts";

describe("extraColumnDefault", () => {
  it.each([
    ["text not null default 'en'", "'en'"],
    ["numeric(5, 2) not null default 8", "8"],
    ["uuid[] default '{}'::uuid[]", "'{}'::uuid[]"],
    ["text default 'not null' not null", "'not null'"],
    ["timestamptz not null default now()", "now()"],
    ["integer default 0 check (value > 0)", "0"],
    ["text not null", undefined],
    ["text", undefined],
  ])("reads the default of %s", (type, expected) => {
    expect(extraColumnDefault(type)).toBe(expected);
  });
});

describe("insertExtraColumns", () => {
  it("writes every extra column and falls back to its default", () => {
    const insert = insertExtraColumns(
      "t",
      [
        { name: "kind", ident: '"kind"', type: "text not null default 'line'" },
        { name: "note", ident: '"note"', type: "text" },
      ],
      "f",
    );

    expect(insert.columns).toBe(', "kind", "note"');
    expect(insert.values).toBe(
      `, case when f ? 'kind' then (jsonb_populate_record(null::t, coalesce(f, '{}'::jsonb)))."kind" else 'line' end, (jsonb_populate_record(null::t, coalesce(f, '{}'::jsonb)))."note"`,
    );
  });
});
