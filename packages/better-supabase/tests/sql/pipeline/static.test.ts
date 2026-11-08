import { describe, expect, it } from "vitest";

import {
  rerunnableDdl,
  staticDdl,
  unwrapGuards,
} from "../../../src/sql/pipeline/static.ts";

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

  it("drops a named check the create table already holds inline", () => {
    const sql = staticDdl(`create table "b"."q" (
  "period" text check ("period" in ('day', 'week')),
  "kind" text
);
alter table "b"."q" drop constraint if exists q_period_check;
alter table "b"."q" add constraint q_period_check check ("period" in ('day', 'week'));
alter table "b"."q" add constraint q_kind_check check ("kind" in ('a'));`);

    expect(sql).not.toContain("q_period_check");
    expect(sql).toContain("q_kind_check");
  });

  it("folds a named check that replaces an inline one into the create table", () => {
    const sql = staticDdl(`create table "b"."t" (
  "scope" text not null default 'a' check ("scope" in ('a', 'b')),
  "x" int,
  check (("scope" = 'a') = ("x" is null))
);
alter table "b"."t" add constraint "t_scope_check" check ("scope" in ('a', 'b', 'c'));
alter table "b"."t" add constraint "t_check" check (("scope" = 'a') = ("x" is not null));
alter table "b"."t" add constraint "t_other_check" check ("x" > 0);`);

    expect(sql).toContain(`check ("scope" in ('a', 'b', 'c'))`);
    expect(sql).toContain(`check (("scope" = 'a') = ("x" is not null))`);
    expect(sql).not.toContain("t_scope_check");
    expect(sql).not.toContain("t_check");
    expect(sql).toContain("t_other_check");
    expect(sql).not.toContain(";;");
  });

  it("folds a named check over an inline constraint of the same name", () => {
    const sql = staticDdl(`create table "b"."t" (
  "scope" text,
  constraint t_system_check check ("scope" = 'a')
);
alter table "b"."t" add constraint t_system_check check (case "scope"::text
  when 'a' then true
  else false end);`);

    expect(sql).toContain("constraint t_system_check check (case");
    expect(sql).not.toContain("add constraint");
  });

  it("moves a check that reads a later column out of the create table", () => {
    const sql = staticDdl(`create table "b"."t" (
  "scope" text check ("scope" in ('a')),
  "x" int,
  constraint t_system_check check ("scope" = 'a')
);
alter table "b"."t" add column if not exists "brand" text;
alter table "b"."t" add constraint t_system_check check ("brand" is null or "scope" = 'a');
alter table "b"."t" add constraint t_scope_check check ("brand" is null);`);

    expect(sql).not.toContain(
      "constraint t_system_check check (\"scope\" = 'a')",
    );
    expect(sql).toContain(
      'add constraint t_system_check check ("brand" is null or',
    );
    expect(sql).toContain('add column "brand" text;');
    expect(sql.indexOf('add column "brand"')).toBeLessThan(
      sql.indexOf("add constraint t_system_check"),
    );
    expect(sql).toContain('"scope" text,');
    expect(sql).toMatch(/"x" int\n\);/);
    expect(sql).not.toContain("check (\"scope\" in ('a'))");
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

describe("unwrapGuards", () => {
  const guarded = `do $$
begin
  if to_regclass('realtime.messages') is not null then
        create policy p on realtime.messages
  for select to authenticated
  using (true);
    drop policy if exists "q" on realtime.messages;
  end if;
end;
$$;
do $tag$ begin
  create type workflow.status as enum ('a', 'b');
exception when duplicate_object then null;
end $tag$;
do $$ begin if to_regclass('public.x') is not null then create table y (); end if; end $$;
select 1;`;

  it("writes a policy on a platform table as a plain statement", () => {
    const out = unwrapGuards(guarded);

    expect(out).toContain(
      "create policy p on realtime.messages\n  for select to authenticated\n  using (true);\ndrop policy",
    );
    expect(out).not.toContain("to_regclass('realtime.messages')");
  });

  it("writes a create type that swallows duplicate_object as one statement", () => {
    expect(unwrapGuards(guarded)).toContain(
      "create type workflow.status as enum ('a', 'b');",
    );
  });

  it("leaves any other do block alone", () => {
    expect(unwrapGuards(guarded)).toContain("to_regclass('public.x')");
  });

  it("feeds staticDdl, which drops the guarded drops too", () => {
    expect(staticDdl(guarded)).not.toContain("drop policy");
  });
});

describe("rerunnableDdl with quoted names", () => {
  it("drops a constraint and a trigger whose quoted name ends the line", () => {
    const sql = rerunnableDdl(`alter table "b"."t" add constraint "c_check"
  check (true);
create trigger "t_trg" before insert on "b"."t"
  for each row execute function f();`);

    expect(sql).toContain('drop constraint if exists "c_check";');
    expect(sql).toContain('drop trigger if exists "t_trg" on "b"."t";');
  });
});

describe("rerunnableDdl over dependents and guards", () => {
  it("keeps a function a policy still calls instead of failing the drop", () => {
    const sql = rerunnableDdl('drop function if exists "b"."f"();\nselect 1;');

    expect(sql).toContain(
      'do $$ begin drop function if exists "b"."f"(); exception when dependent_objects_still_exist then null; end $$;',
    );
    expect(sql).toContain("select 1;");
  });

  it("drops the policy on a Supabase-owned table before it creates it", () => {
    const sql = rerunnableDdl(`do $$
begin
  if to_regclass('realtime.messages') is not null then
    create policy bsb_x_receive on realtime.messages for select to authenticated using (true);
  end if;
end;
$$;`);

    expect(sql).toContain(
      "drop policy if exists bsb_x_receive on realtime.messages;",
    );
  });

  it("keeps the do block that swallows a duplicate type", () => {
    const block = `do $$ begin create type "b"."s" as enum ('a'); exception when duplicate_object then null; end $$;`;

    expect(rerunnableDdl(block)).toContain("exception when duplicate_object");
  });
});

describe("staticDdl with two entities on one table", () => {
  it("declares a trigger and a policy once", () => {
    const sql =
      staticDdl(`create trigger bsb_t before update on "a"."t" for each row execute function f();
create policy bsb_p on "a"."t" for select to authenticated using (true);
create trigger bsb_t before update on "a"."t" for each row execute function f();
create policy bsb_p on "a"."t" for select to authenticated using (true);
create trigger bsb_t before update on "a"."u" for each row execute function f();`);

    expect(sql.match(/create trigger/g)).toHaveLength(2);
    expect(sql.match(/create policy/g)).toHaveLength(1);
  });
});
