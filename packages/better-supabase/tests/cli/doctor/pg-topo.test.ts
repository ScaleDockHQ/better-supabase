import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { RULES } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";

type Files = Record<string, string>;

function run(code: string, files: Files) {
  const rule = RULES.find((candidate) => candidate.code === code)!;

  const context = {
    config: resolveConfig({}, "/p"),
    configToml: undefined,
    sqlFiles: Object.entries(files).map(([path, text]) => ({
      path: `supabase/schemas/${path}`,
      text,
    })),
  };

  // SAFETY: the pg-topo rules read only `sqlFiles` and `configToml`.
  return rule.check(context as unknown as DoctorContext);
}

const base = {
  "a.sql": "create schema app;\ncreate table app.users (id int primary key);",
};

describe("pg-topo doctor group", () => {
  it("is quiet on files that stand on their own", async () => {
    for (const code of ["BS720", "BS721", "BS722", "BS723", "BS724"]) {
      expect({ code, found: await run(code, base) }).toEqual({
        code,
        found: [],
      });
    }
  });

  it("is quiet without schema files", async () => {
    expect(await run("BS721", {})).toEqual([]);
  });

  it("reports a file that does not parse, with its path", async () => {
    const found = await run("BS720", {
      ...base,
      "b.sql": "create tabel nope (",
    });

    expect(found).toHaveLength(1);
    expect(found[0]?.target).toBe("supabase/schemas/b.sql");
  });

  it("accepts a platform schema, a built-in type and a call that uses a default argument", async () => {
    const found = await run("BS721", {
      "a.sql": `create extension if not exists pgcrypto schema extensions;
create table public.t (x xid8);
create function public.f(a text, b text default null) returns void language sql as 'select 1';
create function public.g() returns void language plpgsql as $$ begin perform public.f('a'); end $$;`,
    });

    expect(found).toEqual([]);
  });

  it("accepts extension types, serial types and temporary tables", async () => {
    const found = await run("BS721", {
      "a.sql": `create extension if not exists citext schema extensions;
create extension if not exists vector schema extensions;
create table public.t (id bigserial primary key, n smallserial, email citext, e halfvec(3), v vector(3), s sparsevec(3));
create function public.f() returns void language plpgsql as $$
begin
  create temp table scratch (id int) on commit drop;
  insert into pg_temp.scratch values (1);
end $$;
create function public.g() returns bigint language sql as 'select count(*) from pg_temp.scratch';`,
    });

    expect(found.map((finding) => finding.message)).toEqual([]);
  });

  it("reports a table no file creates, but not the platform's", async () => {
    const found = await run("BS721", {
      "a.sql": `create table app.t (u uuid references auth.users (id), o int references app.orders (id));`,
    });

    expect(found.map((finding) => finding.message).join("\n")).toContain(
      "app.orders",
    );
    expect(found.map((finding) => finding.message).join("\n")).not.toContain(
      "auth.users",
    );
  });

  it("accepts an object a provides annotation declares", async () => {
    const found = await run("BS721", {
      "a.sql": `-- pg-topo:provides table:app.orders
select 1;
create table app.t (o int references app.orders (id));`,
    });

    expect(found.map((finding) => finding.message).join("\n")).not.toContain(
      "table app.orders",
    );
  });

  it("reports two statements that create the same object", async () => {
    const found = await run("BS722", {
      "a.sql": "create schema app; create table app.t (id int);",
      "b.sql": "create table app.t (id int, n text);",
    });

    expect(found.length).toBeGreaterThan(0);
  });

  it("reports an annotation pg-topo cannot read", async () => {
    const found = await run("BS724", {
      "a.sql": "-- pg-topo:phase nonsense\ncreate schema app;",
    });

    expect(found).toHaveLength(1);
  });

  it("reports statements that depend on each other in a cycle", async () => {
    const found = await run("BS723", {
      "a.sql": `create schema app;
create view app.a as select * from app.b;
create view app.b as select * from app.a;`,
    });

    expect(found.length).toBeGreaterThan(0);
    expect(found[0]?.message).toContain("dependency cycle");
  });

  it("leaves the library's module files and files outside the schema folder alone", async () => {
    expect(
      await run("BS721", {
        "_better_supabase/900_better_supabase_001_x.sql":
          "create table app.t (o int references app.orders (id));",
      }),
    ).toEqual([]);

    const rule = RULES.find((candidate) => candidate.code === "BS721")!;

    const context = {
      config: resolveConfig({}, "/p"),
      configToml: undefined,
      sqlFiles: [
        {
          path: "supabase/migrations/1_x.sql",
          text: "create table app.t (o int references app.orders (id));",
        },
      ],
    };

    // SAFETY: the pg-topo rules read only `sqlFiles` and `configToml`.
    expect(await rule.check(context as unknown as DoctorContext)).toEqual([]);
  });

  it("accepts a call to a function a schema file creates under another signature", async () => {
    const found = await run("BS721", {
      "a.sql": `create schema app;
create function app.f(a text, b text default null) returns int language sql as 'select 1';
create view app.v as select app.f('x') as n;`,
    });

    expect(found).toEqual([]);
  });

  it("leaves repeated idempotent schema statements alone", async () => {
    expect(
      await run("BS722", {
        "a.sql": "create schema if not exists app;",
        "b.sql": "create schema if not exists app;",
      }),
    ).toEqual([]);
  });

  it("reads the folder config.toml names for pg-delta", async () => {
    const rule = RULES.find((candidate) => candidate.code === "BS720")!;

    const context = {
      config: resolveConfig({}, "/p"),
      configToml: {
        dir: "supabase",
        document: {
          experimental: { pgdelta: { declarative_schema_path: "./db/" } },
        },
      },
      sqlFiles: [
        { path: "supabase/db/a.sql", text: "create tabel nope (" },
        { path: "supabase/schemas/b.sql", text: "create tabel nope (" },
      ],
    };

    // SAFETY: the pg-topo rules read only `sqlFiles` and `configToml`.
    const found = await rule.check(context as unknown as DoctorContext);

    expect(found.map((finding) => finding.target)).toEqual([
      "supabase/db/a.sql",
    ]);
  });

  it("reports a type and a function of an app schema that no file creates", async () => {
    const found = await run("BS721", {
      "a.sql": `create schema app;
create table app.t (m app.money_t, c public.custom_t);
create view app.v as select app.missing_fn(1) as n;`,
    });

    const text = found.map((finding) => finding.message).join("\n");

    expect(text).toContain("type app.money_t");
    expect(text).toContain("type public.custom_t");
    expect(text).toContain("app.missing_fn");
  });
});
