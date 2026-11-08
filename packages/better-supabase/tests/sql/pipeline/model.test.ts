import { describe, expect, it } from "vitest";

import {
  appColumnsOf,
  buildModel,
  conflicts,
  createParseCache,
  objectKey,
  ownerOf,
  parseDeclared,
} from "../../../src/sql/pipeline/model.ts";
import { splitStatements } from "../../../src/sql/pipeline/split.ts";

const SQL = `
create table if not exists public.tasks (id uuid primary key);
create unique index tasks_id on public.tasks (id);
create index concurrently if not exists "Tasks_x" on tasks (id);
create policy "tasks_read" on public.tasks for select using (true);
create trigger tasks_touch before update on public.tasks for each row execute function public.touch();
create or replace view public.open_tasks as select 1;
create or replace function public.touch(a int, b text) returns void language sql as $$ select 1; $$;
create function public.noargs() returns void language sql as 'select 1';
create type public.state as enum ('a');
create sequence if not exists public.seq;
create schema if not exists extra;
create extension if not exists pgcrypto;
alter table public.tasks add column note text, add column if not exists "Due" date;
alter table public.tasks enable row level security;
comment on table public.tasks is '@bsb subject title=id; it''s';
comment on column public.tasks.id is 'x';
do $$ begin execute format('create table %s ()', 'x'); end $$;
do $$ begin perform 1; end $$;
insert into public.tasks (id) values (gen_random_uuid());
`;

describe("splitStatements", () => {
  it("splits at semicolons outside quotes, bodies and comments", () => {
    const out = splitStatements(
      "select 1; -- x;\nselect ';', $a$;$a$ /* ; */;",
    );

    expect(out.map((statement) => statement.line)).toStrictEqual([1, 2]);
    expect(out).toHaveLength(2);
  });
});

describe("parseDeclared", () => {
  const parsed = parseDeclared(`-- pg-delta: transaction=false\n${SQL}`);
  const names = parsed.objects.map((o) => `${o.kind}:${o.name}`);

  it("reads every created object with its qualified name", () => {
    expect(names).toStrictEqual([
      "table:public.tasks",
      "index:public.tasks_id",
      "index:public.Tasks_x",
      "policy:public.tasks.tasks_read",
      "trigger:public.tasks.tasks_touch",
      "view:public.open_tasks",
      "function:public.touch/2",
      "function:public.noargs/0",
      "type:public.state",
      "sequence:public.seq",
      "schema:extra",
      "extension:pgcrypto",
    ]);
  });

  it("records if not exists", () => {
    expect(
      parsed.objects.find((o) => o.name === "public.tasks")?.ifNotExists,
    ).toBe(true);
    expect(
      parsed.objects.find((o) => o.name === "public.tasks_id")?.ifNotExists,
    ).toBe(false);
    expect(
      parsed.objects.find((o) => o.name === "public.Tasks_x")?.ifNotExists,
    ).toBe(true);
  });

  it("reads added columns, table tags, do blocks and inserts", () => {
    expect(parsed.alters).toStrictEqual([
      {
        table: "public.tasks",
        columns: ["note", "Due"],
        definitions: [
          { name: "note", type: expect.any(String) },
          { name: "Due", type: expect.any(String) },
        ],
        line: expect.any(Number),
      },
    ]);

    expect(parsed.tags).toStrictEqual([
      { table: "public.tasks", tags: "@bsb subject title=id; it's" },
    ]);

    expect(parsed.doBlocks).toHaveLength(1);
    expect(parsed.inserts).toHaveLength(1);
    expect(parsed.outsideTransaction).toBe(true);
  });

  it("is quiet about a file without declarations", () => {
    expect(parseDeclared("select 1;")).toMatchObject({
      objects: [],
      outsideTransaction: false,
    });
  });
});

describe("parse cache", () => {
  it("parses one text once", () => {
    const cache = createParseCache();
    const a = cache.get(SQL);
    const b = cache.get(SQL);
    cache.get("select 1;");

    expect(a).toBe(b);
    expect(cache.stats).toStrictEqual({ parsed: 2, hits: 1 });
  });
});

describe("model", () => {
  const module = `-- better-supabase module: tasks\n-- @bsb-block tasks@2 managed\n\ncreate table public.tasks (id uuid);\ncreate or replace function public.touch(a int) returns void language sql as 'select 1';\n`;
  const data = `-- @bsb-block-data tasks\ncreate or replace function public.touch(a int) returns void language sql as 'select 1';`;
  const app = `create or replace function public.touch(a int) returns void language sql as 'select 2';\nalter table public.tasks add column note text;`;

  it("tells a module file from an app file", () => {
    expect(ownerOf("a.sql", module)).toStrictEqual({
      kind: "module",
      name: "tasks",
    });
    expect(ownerOf("a.sql", data)).toStrictEqual({
      kind: "module",
      name: "tasks",
    });
    expect(ownerOf("app.sql", app)).toStrictEqual({
      kind: "app",
      file: "app.sql",
    });
  });

  it("indexes declarations, alters and conflicts", () => {
    const model = buildModel([
      { path: "m.sql", text: module },
      { path: "d.sql", text: data },
      { path: "app.sql", text: app },
    ]);

    const touch = model.objects.get(objectKey("function", "public.touch/1"));

    expect(touch?.map((d) => d.file)).toStrictEqual([
      "m.sql",
      "d.sql",
      "app.sql",
    ]);
    expect(model.alters.get("public.tasks")).toStrictEqual([
      { owner: { kind: "app", file: "app.sql" }, columns: ["note"] },
    ]);

    expect(conflicts(model).map((c) => c.key)).toStrictEqual([
      "function:public.touch/1",
    ]);
  });

  it("does not call one owner's two files a conflict", () => {
    const model = buildModel([
      { path: "m.sql", text: module },
      { path: "d.sql", text: data },
    ]);

    expect(conflicts(model)).toStrictEqual([]);
  });
});

describe("appColumnsOf", () => {
  it("leaves out the columns the database fills", () => {
    expect(
      appColumnsOf([
        {
          path: "supabase/schemas/tags.sql",
          text: `alter table public.tags
  add column job_id uuid generated always as (id) stored,
  add column seq bigint generated by default as identity,
  add column region text;`,
        },
      ]),
    ).toStrictEqual({ "public.tags": [{ name: "region", type: "text" }] });
  });

  const module =
    "-- @bsb-block tags@1 managed\nalter table public.tags add column region text;";

  it("reads the columns app files add, with their types, and skips module files", () => {
    expect(
      appColumnsOf([
        {
          path: "supabase/schemas/tags.sql",
          text: `alter table public.tags
  add column "locale" text not null default 'en',
  add column if not exists score numeric(5, 2) check (score >= 0),
  add constraint tags_locale_check check (locale <> '');
alter table public.tags add column locale text;`,
        },
        { path: "supabase/schemas/_better_supabase/tags.sql", text: module },
      ]),
    ).toEqual({
      "public.tags": [
        { name: "locale", type: "text not null default 'en'" },
        { name: "score", type: "numeric(5, 2) check (score >= 0)" },
      ],
    });
  });
});
