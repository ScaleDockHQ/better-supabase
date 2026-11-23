import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { redundantNulls } from "../../../src/sql/index.ts";
import { declaredTableColumnsOf } from "../../helpers/facts.ts";
import { renderBlocks } from "../app-columns.ts";

const app = (extra: string): string => `
create table public.absence_kinds (
  id uuid primary key, org_id uuid not null, code text not null, label text not null,
  unit text not null default 'days', paid boolean not null default true,
  tracked boolean not null default true, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()${extra.includes("confidential") ? ",\n  confidential boolean not null default false" : ""}
);
create table public.absences (
  id uuid primary key, org_id uuid not null, user_id uuid not null, kind_id uuid not null,
  starts_on date not null, ends_on date not null, part text not null default 'full',
  days numeric not null, approval_id uuid, approved_at timestamptz, cancelled_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()${extra.includes("start_part") ? ",\n  start_part text,\n  end_part text" : ""}${extra.includes("end_part_only") ? ",\n  end_part text" : ""}
);`;

const BLOCKS: AnyBlocksConfig = {
  leave: {
    tables: { types: "public.absence_kinds", requests: "public.absences" },
    columns: {
      types: {
        tenant: "org_id",
        key: "code",
        name: "label",
        allowance: null,
        carryoverMax: null,
        color: null,
      },
      requests: {
        tenant: "org_id",
        type: "kind_id",
        partial: "part",
        amount: "days",
        note: null,
        cancelledBy: null,
      },
    },
  },
};

const layout = async (text: string, modules: AnyBlocksConfig = BLOCKS) => ({
  modules,
  ownTables: {
    "public.absence_kinds": "app.sql",
    "public.absences": "app.sql",
  },
  ownColumns: Object.fromEntries(
    [...(await declaredTableColumnsOf([{ text }], ["public"]))].map(
      ([table, names]) => [table, [...names]],
    ),
  ),
});

const sql = async (
  extra: string,
  modules: AnyBlocksConfig = BLOCKS,
): Promise<string> =>
  renderBlocks(["leave"], await layout(app(extra), modules))
    .map((file) => file.contents)
    .join("\n");

describe("leave features follow the columns the app's tables declare", () => {
  it("turns the parts of the day on when the table declares both columns", async () => {
    expect(await sql("start_part")).toContain('"start_part"');
    expect(await sql("")).not.toContain('"start_part"');
  });

  it("refuses a table that declares only one part column", async () => {
    await expect(sql("end_part_only")).rejects.toThrow(/startPart and endPart/);
  });

  it("filters confidential types only over a table that declares the column", async () => {
    expect(await sql("confidential")).toContain("lc.");
    expect(await sql("")).not.toContain("lc.");
  });
});

describe("a null for a column the table lacks", () => {
  it("is redundant, and a null for a column the table has is not", async () => {
    const found = redundantNulls(await layout(app("")));

    expect(found.map((entry) => `${entry.logical}.${entry.column}`)).toEqual([
      "types.allowance",
      "types.carryoverMax",
      "types.color",
      "requests.note",
      "requests.cancelledBy",
    ]);
    expect(
      redundantNulls(
        await layout(
          app("").replace("approval_id uuid,", "approval_id uuid, note text,"),
        ),
      ).map((entry) => entry.column),
    ).not.toContain("note");
  });
});
