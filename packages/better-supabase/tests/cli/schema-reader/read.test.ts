import { describe, expect, it } from "vitest";

import { getFileFacts } from "../../../src/cli/schema-reader/index.ts";
import { factsFrom } from "../../../src/cli/schema-reader/read.ts";
import { Source } from "../../../src/cli/schema-reader/source.ts";

describe("factsFrom", () => {
  it("reads column, key, foreign key and check constraints under a search path", async () => {
    const read = await getFileFacts(`set search_path = "$user", app;
create table t (
  id int generated always as identity,
  b int not null default 1 references other match full on delete cascade on update set null initially deferred,
  c int check (c > 0),
  d int,
  e int unique deferrable references other not deferrable,
  constraint k unique nulls not distinct (d),
  foreign key (d) references s.o (x) on delete set default deferrable initially deferred,
  check (d < 9)
);`);

    expect(read.tables[0]).toMatchObject({
      name: "app.t",
      columns: [
        { name: "id", type: "int", hasDefault: true },
        { name: "b", notNull: true, hasDefault: true },
        { name: "c", definition: "int check (c > 0)" },
        { name: "d", definition: "int" },
        { name: "e" },
      ],
      keys: [
        { columns: ["e"] },
        { columns: ["d"], primary: false, nullsNotDistinct: true },
      ],
      foreignKeys: [
        {
          columns: ["b"],
          references: "app.other",
          match: "full",
          onDelete: "cascade",
          onUpdate: "set null",
          deferrable: true,
          initiallyDeferred: true,
        },
        { columns: ["e"], deferrable: false },
        {
          columns: ["d"],
          references: "s.o",
          referencedColumns: ["x"],
          deferrable: true,
          initiallyDeferred: true,
          match: "simple",
          onDelete: "set default",
          onUpdate: "no action",
        },
      ],
      checks: [
        { columns: ["c"], expression: "c > 0" },
        { columns: ["d"], expression: "d < 9" },
      ],
    });
  });

  it("reads a column's deferrable after its initially clause", async () => {
    const read = await getFileFacts(`create table public.t (
  a int references public.o initially immediate deferrable,
  b int references public.o not deferrable initially immediate
);`);

    expect(read.tables[0]?.foreignKeys).toMatchObject([
      { columns: ["a"], deferrable: true, initiallyDeferred: false },
      { columns: ["b"], deferrable: false, initiallyDeferred: false },
    ]);
  });

  it("reads the less common clause forms", async () => {
    const read = await getFileFacts(`set search_path = "$user";
create table t (a int references o);
create view v with (security_barrier) as select 1;
grant all on t to anon;
comment on table t is null;
drop sequence s;`);

    expect(read.tables[0]).toMatchObject({
      name: "public.t",
      foreignKeys: [{ columns: ["a"], references: "public.o" }],
    });
    expect(read.views[0]).toMatchObject({ name: "public.v" });
    expect(read.grants[0]).toMatchObject({
      privileges: [],
      objects: ["public.t"],
    });
    expect(read.drops).toMatchObject([{ kind: "other" }]);
  });

  it("reads alter table commands and every drop kind", async () => {
    const read =
      await getFileFacts(`alter table p add column x int not null, alter column n set not null,
  alter column x drop not null, drop column y, add constraint fk foreign key (x) references public.q,
  add constraint ck check (x > 1), add constraint u unique (x), enable row level security, owner to postgres;
drop table public.p, q; drop materialized view s.m; drop domain dm; drop procedure pr();
drop policy pol on public.p; drop trigger tr on p; drop schema sc;`);

    expect(read.alters[0]).toMatchObject({
      table: "public.p",
      addedColumns: [{ name: "x", notNull: true }],
      setNotNull: ["n"],
      dropNotNull: ["x"],
      droppedColumns: ["y"],
      addedForeignKeys: [
        { name: "fk", columns: ["x"], references: "public.q" },
      ],
      addedChecks: [{ name: "ck", columns: ["x"], expression: "x > 1" }],
      enablesRls: true,
    });
    expect(read.drops.map(({ kind, name }) => `${kind} ${name}`)).toEqual([
      "table public.p",
      "table public.q",
      "view s.m",
      "type public.dm",
      "function public.pr",
      "policy public.p.pol",
      "trigger public.p.tr",
    ]);
  });

  it("reads policies, with public for a policy without roles", async () => {
    const read =
      await getFileFacts(`create policy "r" on s.p as restrictive for select to anon, current_user
  using (true) with check (false);
create policy w on p for update using (a = 1);`);

    expect(read.policies).toMatchObject([
      {
        name: "r",
        table: "s.p",
        command: "select",
        permissive: false,
        roles: ["anon"],
        using: "true",
        withCheck: "false",
        terms:
          "as restrictive for select to anon, current_user using (true) with check (false)",
      },
      {
        name: "w",
        table: "public.p",
        permissive: true,
        roles: ["public"],
        using: "a = 1",
      },
    ]);
    expect(read.policies[1]?.withCheck).toBeUndefined();
  });

  it.each([
    [
      "create unique index on public.p (lower(n));",
      { name: undefined, unique: true, columns: [], plain: false },
    ],
    [
      "create index ix on p using gin (n gin_trgm_ops) where n is not null;",
      {
        method: "gin",
        keys: ["n gin_trgm_ops"],
        plain: false,
        predicate: "n is not null",
      },
    ],
    ['create index iy on p (n collate "C");', { columns: [], plain: false }],
    [
      "create index if not exists iz on p (a, b desc);",
      {
        keys: ["a", "b desc"],
        columns: ["a", "b"],
        plain: true,
        ifNotExists: true,
      },
    ],
  ])("reads %s", async (sql, expected) => {
    expect((await getFileFacts(sql)).indexes[0]).toMatchObject(expected);
  });

  it("reads views, types, functions and triggers", async () => {
    const read =
      await getFileFacts(`create view v (a, b) with (security_invoker = false) as select 1, 2;
create or replace view s.w with (security_invoker) as select * from t;
create materialized view if not exists mv as select 1 as one;
create type pair as (a int, b int);
create type span as range (subtype = int);
create function f(a int default 1) returns int language sql as $$ select 1 $$;
create procedure s.pr(x text) language plpgsql as $$ begin null; end $$;
create function g() returns table (x int) language sql as 'select 1';
create trigger tr before insert or update or delete or truncate on t for each row execute function s.touch();`);

    expect(read.views).toMatchObject([
      {
        name: "public.v",
        columnAliases: ["a", "b"],
        securityInvoker: false,
        updatable: true,
      },
      { name: "s.w", replace: true, securityInvoker: true, columns: undefined },
      {
        name: "public.mv",
        materialized: true,
        columns: ["one"],
        updatable: false,
      },
    ]);
    expect(
      read.declared
        .filter((each) => each.kind === "type")
        .map((each) => each.name),
    ).toEqual(["public.pair", "public.span"]);
    expect(read.functions).toMatchObject([
      {
        name: "public.f",
        signature: "int",
        arity: 1,
        procedure: false,
        body: " select 1 ",
      },
      { name: "s.pr", signature: "text", procedure: true },
      { name: "public.g", arity: 0, body: "select 1" },
    ]);
    expect(read.triggers[0]).toMatchObject({
      table: "public.t",
      function: "s.touch",
      timing: "before",
      events: ["insert", "delete", "update", "truncate"],
    });
  });

  it("reads comments, grants, do blocks, inserts and objects", async () => {
    const read =
      await getFileFacts(`comment on function s.f(int, text[]) is 'fn';
comment on column s.t.c is 'col';
comment on schema app is 'sch';
comment on type pair is 'ty';
comment on policy p on t is 'pol';
grant select, insert on t, s.u to anon, public;
do $$ begin execute 'x'; end $$;
do $$ begin perform 1; end $$;
insert into t values (1);
create sequence if not exists s.seq;
create schema if not exists app;
create extension if not exists vector with schema extensions;
create extension pgcrypto;
create domain email as text;`);

    expect(read.comments).toMatchObject([
      { target: "function", name: "s.f", signature: "int, text[]", text: "fn" },
      { target: "column", name: "s.t.c", signature: undefined },
      { target: "schema", name: "app" },
      { target: "type", name: "public.pair" },
      { target: "other", name: "t.p" },
    ]);
    expect(read.grants[0]).toMatchObject({
      grant: true,
      privileges: ["select", "insert"],
      objectType: "OBJECT_TABLE",
      objects: ["public.t", "s.u"],
      roles: ["anon", "public"],
    });
    expect([read.doBlocks, read.doCreates, read.inserts]).toEqual([
      [7, 8],
      [7],
      [9],
    ]);
    expect(read.objects).toEqual([
      { kind: "sequence", name: "s.seq", line: 10, ifNotExists: true },
      { kind: "schema", name: "app", line: 11, ifNotExists: true },
      {
        kind: "extension",
        name: "vector",
        line: 12,
        ifNotExists: true,
        schema: "extensions",
      },
      { kind: "extension", name: "pgcrypto", line: 13, ifNotExists: false },
      { kind: "type", name: "public.email", line: 14, ifNotExists: false },
    ]);
  });

  it("reads markers, a module header and a statement outside a transaction", async () => {
    const read = await getFileFacts(`-- pg-delta: transaction = false
-- bsb: rename a to b
-- @bsb-rows x
/* -- @bsb-block y */
select 1;`);

    expect(read.markers.map((each) => each.kind)).toEqual([
      "pg-delta",
      "rename",
      "bsb",
    ]);
    expect(read.outsideTransaction).toBe(true);
    expect(read.module).toBe(false);
    expect((await getFileFacts("-- @bsb-block y\nselect 1;")).module).toBe(
      true,
    );
  });

  it("skips a statement without a node and reads an open-ended one to the end", () => {
    const facts = factsFrom(new Source("select 1", []), [
      {},
      { stmt: { InsertStmt: {} } },
    ]);

    expect(facts.inserts).toEqual([1]);
    expect(facts.statements).toEqual([{ line: 1, kind: "InsertStmt" }]);
  });

  it("falls back to defaults for parse nodes without locations or names", () => {
    const facts = factsFrom(new Source("x", []), [
      {
        stmt: {
          CreateStmt: {
            relation: { schemaname: "", relname: "t" },
            tableElts: [
              {
                ColumnDef: {
                  colname: "a",
                  constraints: [
                    { Other: {} },
                    {
                      Constraint: {
                        contype: "CONSTR_FOREIGN",
                        pktable: { relname: "o" },
                        fk_del_action: "z",
                      },
                    },
                    { Constraint: { contype: "CONSTR_ATTR_DEFERRABLE" } },
                    { Constraint: { contype: "CONSTR_CHECK" } },
                  ],
                },
              },
              { Constraint: { contype: "CONSTR_PRIMARY" } },
              { Other: {} },
            ],
          },
        },
      },
      {
        stmt: {
          AlterTableStmt: {
            relation: { relname: "t" },
            cmds: [
              { Other: {} },
              { AlterTableCmd: { subtype: "AT_AddColumn" } },
              { AlterTableCmd: { subtype: "AT_AddConstraint" } },
            ],
          },
        },
      },
      { stmt: { CommentStmt: { objtype: "OBJECT_TABLE" } } },
      { stmt: { CreateTrigStmt: {} } },
      { stmt: { CreatePolicyStmt: {} } },
      {
        stmt: {
          DropStmt: {
            removeType: "OBJECT_SCHEMA",
            objects: [{ List: { items: [{ String: { sval: "s" } }] } }],
          },
        },
      },
    ]);

    expect(facts.tables[0]).toMatchObject({
      name: "public.t",
      columns: [{ name: "a", type: "", definition: "" }],
      keys: [{ columns: [], primary: true }],
      foreignKeys: [
        {
          columns: ["a"],
          deferrable: true,
          onDelete: "no action",
          onUpdate: "no action",
        },
      ],
      checks: [{ columns: ["a"], expression: "" }],
    });
    expect(facts.alters[0]).toMatchObject({
      addedColumns: [],
      addedChecks: [],
      addedForeignKeys: [],
    });
    expect(facts.comments).toEqual([]);
    expect(facts.triggers[0]).toMatchObject({ timing: "after", events: [] });
    expect(facts.policies[0]).toMatchObject({
      command: "all",
      permissive: true,
      roles: [],
    });
    expect(facts.drops).toEqual([
      { kind: "other", name: "public.s", index: 5 },
    ]);
  });

  it("reads a do block with a language and an extension without a schema option", async () => {
    const read =
      await getFileFacts(`do language plpgsql $$ begin create table x (); end $$;
create extension citext with version '1.6';`);

    expect(read.doCreates).toEqual([1]);
    expect(read.objects).toEqual([
      { kind: "extension", name: "citext", line: 2, ifNotExists: false },
    ]);
  });
});
