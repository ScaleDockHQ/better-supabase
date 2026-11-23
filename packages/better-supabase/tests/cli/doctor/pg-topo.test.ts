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
});
