import { describe, expect, it } from "vitest";

import { keyColumnsOf, parseSchema } from "../../src/create/index.ts";

const source = (contents: string) => [{ path: "a.sql", module: "a", contents }];

describe("parseSchema on hand-written SQL", () => {
  it("ignores comments, unterminated blocks and alters of unknown tables", () => {
    const tables = parseSchema(
      source(`
        -- create table public.ghost (id int);
        create table public.notes (id uuid primary key, body text);
        alter table public.missing add column x int;
        /* unterminated`),
    );

    expect(tables.map((table) => table.name)).toEqual(["notes"]);
  });
});

describe("keyColumnsOf", () => {
  it("adds soft reference columns to the keys", () => {
    const [notes] = parseSchema(
      source(
        "create table public.notes (id uuid primary key, body text, owner uuid);",
      ),
    );

    expect(
      keyColumnsOf(notes!, new Set(["owner"])).map((column) => column.name),
    ).toEqual(["id", "owner"]);
  });
});
