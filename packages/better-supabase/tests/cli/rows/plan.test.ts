import { describe, expect, it } from "vitest";

import { planRows } from "../../../src/cli/rows/plan.ts";
import {
  DeclaredRowsError,
  deleteStatement,
  getDeclaredFile,
} from "../../../src/cli/rows/read.ts";

const NOW = new Date("2026-11-22T10:00:00Z");

const upsert = (...labels: string[]): string =>
  `insert into better_supabase.declared_defaults (kind, subject, key, position, value)
values
${labels
  .map(
    (label, index) =>
      `  ('option_set_item', 'project.priority', '${label}', ${String(index)}, jsonb_build_object('label', '${label}'))`,
  )
  .join(",\n")}
on conflict (kind, subject, key) do update set position = excluded.position, value = excluded.value;
`;

describe("readDeclaredFile", () => {
  it("reads the natural key of every row", async () => {
    const file = await getDeclaredFile("priorities", upsert("low", "high"));

    expect(file.upserts[0]?.rows.map((row) => row.key)).toEqual([
      ["option_set_item", "project.priority", "low"],
      ["option_set_item", "project.priority", "high"],
    ]);
    expect(file.hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("ignores whitespace and comments in the hash", async () => {
    const a = await getDeclaredFile("p", upsert("low"));

    const b = await getDeclaredFile(
      "p",
      `-- note\n${upsert("low").replaceAll("\n", "\n\n")}`,
    );

    expect(b.hash).toBe(a.hash);
  });

  it.each([
    ["do nothing", "insert into t (a) values (1) on conflict (a) do nothing;"],
    ["no conflict clause", "insert into t (a) values (1);"],
    [
      "a select source",
      "insert into t (a) select 1 on conflict (a) do update set a = 1;",
    ],
    ["another statement", "delete from t;"],
    [
      "a function",
      "insert into t (a, b) values (1, now()) on conflict (a) do update set b = excluded.b;",
    ],
    [
      "a non literal key",
      "insert into t (a) values (random()) on conflict (a) do update set a = excluded.a;",
    ],
    [
      "a with clause",
      "with s as (select 1) insert into t (a) values (1) on conflict (a) do update set a = 1;",
    ],
    [
      "a returning clause",
      "insert into t (a) values (1) on conflict (a) do update set a = 1 returning a;",
    ],
    [
      "a constraint target",
      "insert into t (a) values (1) on conflict on constraint t_pkey do update set a = 1;",
    ],
    [
      "a key it does not insert",
      "insert into t (b) values (1) on conflict (a) do update set b = 1;",
    ],
    [
      "a short row",
      "insert into t (a, b) values (1) on conflict (a) do update set b = 1;",
    ],
    [
      "a subquery",
      "insert into t (a, b) values (1, (select 2)) on conflict (a) do update set b = 1;",
    ],
    [
      "an expression key",
      "insert into t (a) values ('x') on conflict ((lower(a))) do update set a = 1;",
    ],
    [
      "a nested function",
      "insert into t (a, b) values (1, jsonb_build_object('at', now())) on conflict (a) do update set b = 1;",
    ],
    [
      "a null key",
      "insert into t (a) values (null) on conflict (a) do update set a = 1;",
    ],
  ])("rejects %s", async (_name, sql) => {
    await expect(getDeclaredFile("bad", sql)).rejects.toThrow(
      DeclaredRowsError,
    );
  });

  it("reads every literal kind, through casts, without a closing semicolon", async () => {
    const file = await getDeclaredFile(
      "kinds",
      "-- lead\ninsert into s.t (a, b, c, d, e) values ('x'::text, 2, 1.5, true, to_jsonb(1)) on conflict (a, b, c, d) do update set e = excluded.e",
    );

    expect(file.upserts[0]).toMatchObject({
      table: "s.t",
      text: expect.stringMatching(/^insert into s\.t/),
      rows: [{ keyColumns: ["a", "b", "c", "d"], key: ["x", 2, 1.5, true] }],
    });
    expect(file.deleteRemoved).toBe(false);
  });
});

describe("deleteStatement", () => {
  it("quotes identifiers and string keys", () => {
    expect(
      deleteStatement({
        table: 'pub.t"x',
        keyColumns: ["a", "b"],
        key: ["it's", 3],
      }),
    ).toBe(`delete from "pub"."t""x" where "a" = 'it''s' and "b" = 3;`);
  });
});

describe("planRows", () => {
  const files = new Map([["priorities", upsert("low", "high")]]);

  it("writes a stamped migration for a new file", async () => {
    const plan = await planRows(files, new Map(), NOW);

    expect(plan.migrations).toHaveLength(1);
    expect(plan.migrations[0]?.file).toMatch(
      /^20261122\d{6}_declared_rows_priorities_v2-[0-9a-f]{8}\.sql$/,
    );
    expect(plan.migrations[0]?.text).toContain(
      "-- @bsb-rows priorities sha256:",
    );
  });

  it("skips a file whose latest migration has its hash", async () => {
    const first = await planRows(files, new Map(), NOW);
    const migrations = new Map(first.migrations.map((m) => [m.file, m.text]));
    const again = await planRows(files, migrations, NOW);

    expect(again.migrations).toEqual([]);
    expect(again.current).toEqual(["priorities"]);
  });

  it("writes a new migration for a changed file and reports a removed row", async () => {
    const first = await planRows(files, new Map(), NOW);
    const migrations = new Map(first.migrations.map((m) => [m.file, m.text]));

    const next = await planRows(
      new Map([["priorities", upsert("low")]]),
      migrations,
      NOW,
    );

    expect(next.migrations).toHaveLength(1);
    expect(next.migrations[0]?.file).not.toBe(first.migrations[0]?.file);
    expect(next.review[0]).toContain("stays in the database");
    expect(next.migrations[0]?.text).not.toMatch(/^delete from/m);
  });

  it("deletes a removed row only when the file opts in", async () => {
    const first = await planRows(files, new Map(), NOW);
    const migrations = new Map(first.migrations.map((m) => [m.file, m.text]));

    const next = await planRows(
      new Map([
        ["priorities", `-- bsb-rows: delete-removed\n${upsert("low")}`],
      ]),
      migrations,
      NOW,
    );

    expect(next.migrations[0]?.text).toContain(
      `delete from "better_supabase"."declared_defaults" where "kind" = 'option_set_item' and "subject" = 'project.priority' and "key" = 'high';`,
    );
  });
});
