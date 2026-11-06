import { describe, expect, it } from "vitest";

import { rerunnableDdl, staticDdl } from "../../../src/sql/pipeline/static.ts";

const FILE = `-- the table
create table if not exists "b"."t" (
  id uuid primary key,
  "ends_at" timestamptz,
  constraint x check (a > 1)
);
alter table "b"."t" add column if not exists "ends_at" timestamptz;
alter table "b"."t" add column if not exists "note" text, add column if not exists "ends_at" timestamptz;
create unique index if not exists i on "b"."t" (id);
drop policy if exists p on "b"."t";
drop trigger if exists tr on "b"."t";
drop function if exists b.f(uuid);
alter table "b"."t" drop constraint if exists x;
create policy p on "b"."t" for select to authenticated using (true);
`;

describe("staticDdl", () => {
  const out = staticDdl(FILE);

  it("removes the drops a schema diff makes unnecessary", () => {
    expect(out).not.toContain("drop policy");
    expect(out).not.toContain("drop trigger");
    expect(out).not.toContain("drop function");
    expect(out).not.toContain("drop constraint");
    expect(out).toContain("create policy p on");
  });

  it("removes if not exists from tables, indexes and owned columns", () => {
    expect(out).toContain('create table "b"."t" (');
    expect(out).toContain('create unique index i on "b"."t" (id);');
    expect(out).not.toContain("if not exists");
  });

  it("adds a column once, not when the create table declares it", () => {
    expect(out).not.toContain('add column "ends_at"');
    expect(out).toContain('add column "note" text;');
    expect(out).toContain("-- the table");
  });

  it("keeps if not exists on the columns and indexes of an app table", () => {
    const sql = staticDdl(
      `alter table "public"."notes" add column "x" text;
create index if not exists n_idx on "public"."notes" (id);`,
      new Set(["public.notes"]),
    );

    expect(sql).toContain('add column if not exists "x" text;');
    expect(sql).toContain("create index if not exists n_idx");
  });

  it("keeps everything with keepIfNotExists and drops only the drops", () => {
    const sql = staticDdl(FILE, new Set(), { keepIfNotExists: true });

    expect(sql).toContain('create table if not exists "b"."t" (');
    expect(sql).toContain('add column if not exists "note" text');
    expect(sql).not.toContain("drop policy");
  });

  it("leaves statements inside a function body alone", () => {
    const sql = `create function f() returns void language plpgsql as $$
begin
  drop policy if exists p on t;
  create table if not exists x (id int);
end;
$$;`;

    expect(staticDdl(sql)).toBe(sql);
  });
});

describe("rerunnableDdl", () => {
  it("drops before it creates and guards the columns it adds", () => {
    const sql =
      rerunnableDdl(`create policy p on "b"."t" for select to public using (true);
create trigger tr before update on "b"."t" for each row execute function f();
alter table "b"."t" add constraint c check (a > 1);
alter table "b"."t" add column "note" text;
create index i on "b"."t" (id);`);

    expect(sql).toContain(
      'drop policy if exists p on "b"."t";\ncreate policy p',
    );
    expect(sql).toContain(
      'drop trigger if exists tr on "b"."t";\ncreate trigger',
    );
    expect(sql).toContain(
      'alter table "b"."t" drop constraint if exists c;\nalter table "b"."t" add constraint c',
    );
    expect(sql).toContain('add column if not exists "note" text');
    expect(sql).toContain('create index i on "b"."t" (id);');
  });

  it("round-trips: static, then rerunnable, repeats safely", () => {
    const sql = rerunnableDdl(staticDdl(FILE));

    expect(sql).toContain('drop policy if exists p on "b"."t";');
  });
});
