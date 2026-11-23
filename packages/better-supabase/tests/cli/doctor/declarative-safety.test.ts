import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { RULES } from "../../../src/cli/doctor/rules.ts";
import { supabaseConfigFromText } from "../../../src/cli/supabase-config.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const PGDELTA = "[experimental.pgdelta]\nenabled = true\n";

function run(code: string, files: Record<string, string>, tomlText = PGDELTA) {
  const rule = RULES.find((candidate) => candidate.code === code)!;

  const context = {
    config: resolveConfig({}, "/project"),
    configToml: supabaseConfigFromText(tomlText),
    sqlFiles: Object.entries(files).map(([path, text]) => ({ path, text })),
  };

  // SAFETY: these rules read only `config`, `configToml` and `sqlFiles`.
  return rule.check(context as unknown as DoctorContext);
}

const schema = (name: string) => `supabase/schemas/${name}`;

describe("BS725 statements pg-delta cannot see", () => {
  it("flags a do block that runs DDL, with its line", async () => {
    const found = await run("BS725", {
      [schema("a.sql")]:
        "create table t (id int);\ndo $$ begin create index on t (id); end $$;",
    });

    expect(found).toHaveLength(1);
    expect(found[0]?.location).toEqual({ file: schema("a.sql"), line: 2 });
  });

  it("leaves a do block without DDL, comments and migrations alone", async () => {
    expect(
      await run("BS725", {
        [schema("a.sql")]:
          "-- do $$ begin create table x (); end $$;\ndo $$ begin raise notice 'x'; end $$;",
        "supabase/migrations/1_a.sql": "do $$ begin create table x(); end $$;",
      }),
    ).toEqual([]);
  });

  it("flags cron.schedule in a function body but not at the top", async () => {
    const found = await run("BS725", {
      [schema("a.sql")]: [
        "select cron.schedule('a', '1 second', 'select 1');",
        "create function f() returns void language plpgsql as $$ begin perform cron.schedule('b', '1 second', 'select 1'); end $$;",
      ].join("\n"),
    });

    expect(found.map((finding) => finding.message).join("\n")).toContain(
      "cron.schedule inside a function",
    );
    expect(found).toHaveLength(1);
  });

  it("flags alter publication through execute", async () => {
    const found = await run("BS725", {
      [schema("a.sql")]:
        "do $$ begin execute format('alter publication supabase_realtime add table %s', 't'); end $$;",
    });

    expect(found.some((f) => f.message.includes("publication"))).toBe(true);
  });

  it("flags default privileges without for role only", async () => {
    const found = await run("BS725", {
      [schema("a.sql")]: [
        "alter default privileges in schema app revoke all on tables from anon;",
        "alter default privileges for role postgres in schema app revoke all on tables from anon;",
      ].join("\n"),
    });

    expect(found).toHaveLength(1);
    expect(found[0]?.location?.line).toBe(1);
  });

  it("reads module files too and names the module that wrote them", async () => {
    const found = await run("BS725", {
      [schema("900_better_supabase_050_queue.sql")]: [
        "-- @bsb-block queue@3 managed",
        "create function f() returns void language plpgsql as $$ begin perform cron.schedule('a', '1 minute', 'select 1'); end $$;",
      ].join("\n"),
    });

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("module queue");
    expect(found[0]?.message).toContain("regenerate");
  });

  it("accepts a cron.schedule that checks pg_cron is installed first", async () => {
    expect(
      await run("BS725", {
        [schema("a.sql")]:
          "do $$ begin if pg_catalog.to_regnamespace('cron') is not null then perform cron.schedule('a', '1 minute', 'select 1'); end if; end $$;",
      }),
    ).toEqual([]);
  });

  it("ignores a cron.schedule lookup that only checks the function exists", async () => {
    expect(
      await run("BS725", {
        [schema("a.sql")]:
          "create function f() returns void language plpgsql as $$ begin if to_regprocedure('cron.schedule(text, text, text)') is not null then null; end if; end $$;",
      }),
    ).toEqual([]);
  });

  it("is quiet without pg-delta", async () => {
    expect(
      await run(
        "BS725",
        {
          [schema("a.sql")]:
            "alter default privileges revoke all on tables from anon;",
        },
        "[db]\n",
      ),
    ).toEqual([]);
  });
});

describe("BS726 reserved names", () => {
  it("flags a schema named _custom or _cluster", async () => {
    const found = await run("BS726", {
      [schema("a.sql")]: "create schema if not exists _Custom;",
    });

    expect(found).toHaveLength(1);
  });

  it("flags a folder that differs from _cluster only in case", async () => {
    const found = await run("BS726", {
      [schema("_Cluster/roles.sql")]: "select 1;",
      [schema("_cluster/roles.sql")]: "select 1;",
    });

    expect(found.map((finding) => finding.target)).toEqual([
      schema("_Cluster/roles.sql"),
    ]);
  });
});

describe("BS727 schema_paths with pg-delta", () => {
  it("flags the list only when pg-delta is on", async () => {
    const paths = `${PGDELTA}[db.migrations]\nschema_paths = ["./schemas/a.sql"]\n`;

    expect(await run("BS727", {}, paths)).toHaveLength(1);
    expect(
      await run(
        "BS727",
        {},
        '[db.migrations]\nschema_paths = ["./schemas/a.sql"]\n',
      ),
    ).toEqual([]);
    expect(await run("BS727", {})).toEqual([]);
  });
});

describe("BS728 and BS729 _custom files", () => {
  it("asks for a migration directive and checks that the migration exists", async () => {
    const found = await run("BS728", {
      [schema("_custom/none.sql")]:
        "-- pgdelta-migration: none\ncreate cast x;",
      [schema("_custom/missing.sql")]: "create operator + (leftarg = int);",
      [schema("_custom/dangling.sql")]:
        "-- pgdelta-migration: ../../migrations/9_gone.sql\nselect 1;",
      [schema("_custom/linked.sql")]:
        "-- pgdelta-migration: ../../migrations/1_cast.sql\nselect 1;",
      "supabase/migrations/1_cast.sql": "select 1;",
    });

    expect(
      found
        .map((finding) => finding.target)
        .toSorted((a, b) => String(a).localeCompare(String(b))),
    ).toEqual([schema("_custom/dangling.sql"), schema("_custom/missing.sql")]);
  });

  it("flags a modeled object in _custom but not a cast", async () => {
    const found = await run("BS729", {
      [schema("_custom/a.sql")]: "create cast (int as text) with inout;",
      [schema("_custom/b.sql")]: "create table t (id int);",
    });

    expect(found.map((finding) => finding.target)).toEqual([
      schema("_custom/b.sql"),
    ]);
  });
});

describe("BS730 Pipelines readiness", () => {
  const files = (extra: string) => ({
    [schema("a.sql")]: [
      "create table public.keyed (id int primary key);",
      "create table public.loose (id int, n text);",
      "create table public.full (id int);",
      "alter table public.full replica identity full;",
      extra,
    ].join("\n"),
  });

  it("flags a published table without a key", async () => {
    const found = await run(
      "BS730",
      files(
        "create publication etl for table public.keyed, public.loose, public.full;",
      ),
    );

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("public.loose");
  });

  it("leaves supabase_realtime and unpublished tables alone", async () => {
    expect(
      await run(
        "BS730",
        files("alter publication supabase_realtime add table public.loose;"),
      ),
    ).toEqual([]);
  });
});
