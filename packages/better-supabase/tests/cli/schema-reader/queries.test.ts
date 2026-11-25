import { describe, expect, it } from "vitest";

import { getFileFacts } from "../../../src/cli/schema-reader/index.ts";
import * as q from "../../../src/cli/schema-reader/queries.ts";

const read = (...texts: string[]) =>
  Promise.all(texts.map((text) => getFileFacts(text)));

describe("schema reader queries", () => {
  it("tracks tables, column types and row level security through drops", async () => {
    const files = await read(
      `create table public.a (id int, name text);
create table private.hidden (id int);
create table public.b (id int);
alter table public.a enable row level security;
alter table private.hidden enable row level security;
alter table public.b enable row level security;
drop table public.b;`,
      `create table public.a (extra uuid);
alter table public.a add column note text, add column n int;
alter table private.hidden add column x int;
alter table public.a drop column name;
alter table public.a enable row level security;`,
    );

    expect(q.declaredTables(files, ["public"])).toEqual(["public.a"]);
    expect(q.declaredColumnTypes(files, ["public"])).toEqual(
      new Map([
        [
          "public.a",
          new Map([
            ["id", "int"],
            ["name", "text"],
            ["extra", "uuid"],
          ]),
        ],
        ["public.b", new Map([["id", "int"]])],
      ]),
    );
    expect(q.declaredTableColumns(files, ["public"]).get("public.a")).toEqual(
      new Set(["id", "name", "extra"]),
    );
    expect(q.addedColumnTypes(files, ["public"])).toEqual(
      new Map([
        [
          "public.a",
          new Map([
            ["note", "text"],
            ["n", "int"],
          ]),
        ],
      ]),
    );
    expect(q.rlsTables(files, ["public"])).toEqual(["public.a"]);
  });

  it("marks a view with an instead of trigger updatable and forgets a dropped one", async () => {
    const files =
      await read(`create view public.v as select a, b from t group by a, b;
create view public.gone as select 1 as one;
create view private.p as select 1 as one;
create trigger w instead of insert on public.v for each row execute function f();
create trigger x instead of insert on public.missing for each row execute function f();
drop view public.gone;`);

    expect([...q.declaredViews(files, ["public"])]).toEqual([
      ["public.v", { columns: ["a", "b"], updatable: true }],
    ]);
  });

  it("derives grants from permissive policies, after policy and table drops", async () => {
    const files =
      await read(`create policy all_anon on public.t for all to anon using (true);
create policy own on public.t for select using (true);
create policy staff on public.t for delete to service_role using (true);
create policy strict on public.t as restrictive for update to authenticated using (true);
create policy old on public.t for insert to authenticated with check (true);
drop policy old on public.t;
create policy a on public.a for update to public using (true);
create policy gone on public.z for select to anon using (true);
drop table public.z;
create policy hidden on private.h for select to anon using (true);`);

    expect(q.policyGrants(files, ["public"])).toEqual([
      { table: "public.a", role: "authenticated", privileges: ["update"] },
      {
        table: "public.t",
        role: "anon",
        privileges: ["select", "insert", "update", "delete"],
      },
      { table: "public.t", role: "authenticated", privileges: ["select"] },
    ]);
  });

  it("finds updated_at triggers by function name, setter body or track_updated_at", async () => {
    const files =
      await read(`create function public.bump() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
create trigger a_bump before update on public.a for each row execute function public.bump();
create trigger b_touch before update on public.b for each row execute function extensions.moddatetime(updated_at);
create trigger bsb_c before update on public.c for each row execute function touch();
create trigger d_ins before insert on public.d for each row execute function touch();
create trigger e_other before update on public.e for each row execute function audit();
create trigger h_touch before update on private.h for each row execute function touch();
select track_updated_at('f');
select better_supabase.track_updated_at('s.g');
select track_updated_at();
select other_call('x');`);

    expect(q.declaredUpdatedAtTriggers(files, ["public", "s"])).toEqual({
      "public.a": "a_bump",
      "public.b": "b_touch",
      "public.f": "bsb_updated_at",
      "s.g": "bsb_updated_at",
    });
  });

  it("resolves foreign key targets from the primary key, else id", async () => {
    const files = await read(
      `create table public.p (code text primary key);
create table public.c (p text references public.p, q int references public.q, r int references public.p (code) deferrable);`,
      `alter table public.c add constraint fk foreign key (q) references public.p (code);
create table private.x (p text references public.p);`,
    );

    expect(q.declaredForeignKeys(files, ["public"])).toEqual([
      {
        table: "public.c",
        columns: ["p"],
        references: "public.p",
        referencedColumns: ["code"],
      },
      {
        table: "public.c",
        columns: ["q"],
        references: "public.q",
        referencedColumns: ["id"],
      },
      {
        table: "public.c",
        columns: ["r"],
        references: "public.p",
        referencedColumns: ["code"],
        deferrable: true,
      },
      {
        table: "public.c",
        columns: ["q"],
        references: "public.p",
        referencedColumns: ["code"],
      },
    ]);
  });

  it("lists plain, partial and non-btree indexes with the table keys", async () => {
    const files =
      await read(`create table public.t (id int primary key, a int, b int, unique nulls not distinct (b));
create unique index t_a on public.t (a) where (a is not null);
create index t_b on public.t (b) where b > 0;
create index t_g on public.t using gin (a);
create index t_e on public.t (lower(b));
create index t_p on private.p (a);`);

    expect(q.declaredIndexes(files, ["public"]).get("public.t")).toEqual([
      { name: "t_a", columns: ["a"], unique: true, plain: true },
      { name: "t_b", columns: ["b"], plain: true, where: "where b > 0" },
      { name: "t_g", columns: ["a"], plain: true, method: "gin" },
      { columns: ["id"], unique: true, plain: true },
    ]);
  });

  it("reads the extension schema from the app's own files only", async () => {
    const files = await read(
      "-- @bsb-block x\ncreate extension vector with schema blocks;",
      "create extension pgcrypto;",
      "create extension vector with schema extensions;",
    );

    expect(q.extensionSchema(files, "vector")).toBe("extensions");
    expect(q.extensionSchema(files, "pgcrypto")).toBeUndefined();
  });
});
