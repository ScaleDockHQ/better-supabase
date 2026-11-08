import { describe, expect, it } from "vitest";

import { ownedColumnFiles } from "../../src/cli/codemod-owned-columns.ts";
import { ownedColumns } from "../../src/sql/owned-columns.ts";

const APP = [
  {
    text: `create table public.tasks (id uuid primary key, name text, rank text);
create table public.notes (id uuid primary key);
alter table public.notes add column pinned boolean;`,
  },
];

const RENDERED = [
  {
    contents: `-- a block
alter table "public"."tasks" add column if not exists "rank" text;
alter table "public"."tasks" add column if not exists "archived_at" timestamptz;
alter table "public"."tasks" add column if not exists "archived_at" timestamptz;
alter table "public"."notes" add column if not exists "pinned" boolean;
alter table "public"."notes" add column if not exists "color" text default 'x';
alter table "better_supabase"."tags" add column if not exists "rank" text;
-- alter table "public"."tasks" add column if not exists "hidden" boolean;`,
  },
];

describe("ownedColumns", () => {
  it("finds the columns a block adds that the app's files lack", () => {
    expect(
      ownedColumns(RENDERED, APP, ["public"]).map(
        (entry) => `${entry.table}.${entry.column}`,
      ),
    ).toEqual(["public.tasks.archived_at", "public.notes.color"]);
  });

  it("keeps the block's statement as written", () => {
    expect(ownedColumns(RENDERED, APP, ["public"])[1]?.statement).toBe(
      `alter table "public"."notes" add column if not exists "color" text default 'x';`,
    );
  });

  it("finds nothing once the files declare the columns", () => {
    const files = ownedColumnFiles(
      ownedColumns(RENDERED, APP, ["public"]),
      "supabase/schemas",
    );

    expect(files.map((file) => file.path)).toEqual([
      "supabase/schemas/tasks.block-columns.sql",
      "supabase/schemas/notes.block-columns.sql",
    ]);
    expect(files[0]?.contents).toContain(
      `add column if not exists "archived_at" timestamptz;`,
    );
    expect(
      ownedColumns(
        RENDERED,
        [...APP, ...files.map((file) => ({ text: file.contents }))],
        ["public"],
      ),
    ).toEqual([]);
  });
});
