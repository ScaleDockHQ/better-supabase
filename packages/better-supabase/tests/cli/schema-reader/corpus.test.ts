import { describe, expect, it } from "vitest";

import { readFileFacts } from "../../../src/cli/schema-reader/index.ts";

const facts = readFileFacts;

describe("the schema reader reads what the text scanners got wrong", () => {
  it("keeps a begin atomic body and an escaped string in one statement", async () => {
    const read = await facts(`create function public.f() returns int
language sql
begin atomic
  select 1;
  select 2;
end;
comment on table public.t is E'it\\'s; fine';
create table public.t (id int);`);

    expect(read.statements.map((each) => each.kind)).toEqual([
      "CreateFunctionStmt",
      "CommentStmt",
      "CreateStmt",
    ]);
    expect(read.comments[0]?.text).toBe("it's; fine");
  });

  it("reads DDL inside a string or a do block as no declaration", async () => {
    const read = await facts(`select 'create table public.fake (id int)';
do $$ begin execute 'create table public.also_fake (id int)'; end $$;`);

    expect(read.tables).toEqual([]);
    expect(read.doBlocks).toEqual([2]);
  });

  it("reads temp, partition of, like and create table as", async () => {
    const read = await facts(`create temp table scratch (id int);
create table public.parent (id int, at date) partition by range (at);
create table public.child partition of public.parent for values from ('2020-01-01') to ('2021-01-01');
create table public.copy (like public.parent including all);
create table public.snap as select 1 as one;`);

    expect(
      read.tables.map((each) => [
        each.name,
        each.temporary,
        each.partitionOf,
        each.columnsElsewhere,
      ]),
    ).toEqual([
      ["public.scratch", true, undefined, false],
      ["public.parent", false, undefined, false],
      ["public.child", false, "public.parent", false],
      ["public.copy", false, undefined, true],
      ["public.snap", false, undefined, true],
    ]);
  });

  it("reads every action of a multi-action alter table", async () => {
    const read = await facts(`alter table public.t
  add column a int,
  add column b numeric(10, 2) not null default 0,
  alter column c set not null,
  drop column d,
  enable row level security;`);

    expect(read.alters[0]).toMatchObject({
      table: "public.t",
      setNotNull: ["c"],
      droppedColumns: ["d"],
      enablesRls: true,
    });
    expect(read.alters[0]?.addedColumns.map((c) => [c.name, c.type])).toEqual([
      ["a", "int"],
      ["b", "numeric(10, 2)"],
    ]);
  });

  it("keeps overloads apart and reads a function with no dollar body", async () => {
    const read =
      await facts(`create function public.f(a int) returns int language sql return a;
create function public.f(a text, b int default 1) returns int language sql return 1;
create function public.g() returns int language sql return 2;`);

    expect(read.functions.map((each) => [each.name, each.signature])).toEqual([
      ["public.f", "int"],
      ["public.f", "text, int"],
      ["public.g", ""],
    ]);
  });

  it("reads a numeric type with a comma and a check that says null", async () => {
    const read = await facts(
      `create table public.t (price numeric(10,2) not null, role text check (role is null or tenant is not null), tenant uuid);`,
    );

    const table = read.tables[0]!;

    expect(table.columns.map((c) => [c.name, c.type, c.notNull])).toEqual([
      ["price", "numeric(10,2)", true],
      ["role", "text", false],
      ["tenant", "uuid", false],
    ]);
  });

  it("decodes a comment written as E'' or $$$$ and keeps its tags", async () => {
    const read =
      await facts(`comment on table public.a is E'@bsb access\\nsecond';
comment on table public.b is $$@bsb access$$;`);

    expect(read.comments.map((each) => each.text)).toEqual([
      "@bsb access\nsecond",
      "@bsb access",
    ]);
  });

  it("follows set search_path and does not split a quoted dot", async () => {
    const read = await facts(`create table "my.table" (id int);
set search_path to app, public;
create table things (id int);`);

    expect(read.tables.map((each) => each.name)).toEqual([
      "public.my.table",
      "app.things",
    ]);
  });

  it("reads a CRLF file, its markers and its lines", async () => {
    const read = await facts(
      "-- @bsb-hash: abc\r\n-- pg-delta: transaction=false\r\ncreate table public.t (id int);\r\n",
    );

    expect(read.markers.map((each) => [each.kind, each.line])).toEqual([
      ["bsb", 1],
      ["pg-delta", 2],
    ]);
    expect(read.outsideTransaction).toBe(true);
    expect(read.tables[0]?.line).toBe(3);
  });

  it("reports the file, line and column of a syntax error", async () => {
    await expect(
      facts("select 1;\ncreate table (;", { path: "a.sql" }),
    ).rejects.toThrow(/^a\.sql:2:/u);
  });

  it("reads foreign keys with their match type and deferral", async () => {
    const read = await facts(`create table public.a (
  id int primary key,
  b int references public.b (id),
  c int,
  foreign key (c) references public.c (id) match full on delete cascade deferrable initially deferred
);`);

    expect(read.tables[0]?.foreignKeys).toMatchObject([
      {
        columns: ["b"],
        references: "public.b",
        match: "simple",
        deferrable: false,
      },
      {
        columns: ["c"],
        match: "full",
        deferrable: true,
        initiallyDeferred: true,
        onDelete: "cascade",
      },
    ]);
  });
});
