import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { OWNERSHIP_RULES } from "../../../src/cli/doctor/ownership.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const MODULE = `-- better-supabase module: tasks
-- @bsb-block tasks@1 managed

create table public.tasks (id uuid primary key);
create or replace function public.touch() returns void language sql as 'select 1';
`;

const MIGRATIONS = { database: { sql: { workflow: "migrations" as const } } };

const run = (
  files: readonly { path: string; text: string }[],
  config: Parameters<typeof resolveConfig>[0] = MIGRATIONS,
): { code: string; message: string }[] => {
  // SAFETY: the rules read only `sqlFiles`, `config` and `configToml`.
  const context = {
    sqlFiles: files,
    config: resolveConfig(config, "/p"),
    configToml: undefined,
  } as unknown as DoctorContext;

  return OWNERSHIP_RULES.flatMap((rule) =>
    (rule.check(context) as { message: string }[]).map((finding) => ({
      code: rule.code,
      message: finding.message,
    })),
  );
};

describe("BS369", () => {
  it("flags an app file that creates a table a module creates", () => {
    const found = run([
      { path: "supabase/schemas/010_tasks.sql", text: MODULE },
      {
        path: "supabase/schemas/app.sql",
        text: "create table public.tasks (id uuid primary key, note text);",
      },
    ]);

    expect(found).toHaveLength(1);
    expect(found[0]).toMatchObject({ code: "BS369" });
    expect(found[0]?.message).toContain("public.tasks");
    expect(found[0]?.message).toContain("tasks module");
  });

  it("accepts an app file that alters the module's table", () => {
    expect(
      run([
        { path: "supabase/schemas/010_tasks.sql", text: MODULE },
        {
          path: "supabase/schemas/app.sql",
          text: "alter table public.tasks add column note text;",
        },
      ]),
    ).toStrictEqual([]);
  });

  it("ignores migrations, data files and modules that share a helper", () => {
    const other = MODULE.replace("@bsb-block tasks", "@bsb-block files");

    expect(
      run([
        { path: "supabase/schemas/010_tasks.sql", text: MODULE },
        { path: "supabase/schemas/011_files.sql", text: other },
        {
          path: "supabase/migrations/1_x.sql",
          text: "create table public.tasks (id uuid);",
        },
        {
          path: "better-supabase-data/x.sql",
          text: "create table public.tasks (id uuid);",
        },
      ]).filter((finding) => finding.code === "BS369"),
    ).toStrictEqual([]);
  });

  it("works without schema files", () => {
    // SAFETY: the rules read only `sqlFiles`.
    const context = {} as unknown as DoctorContext;

    expect(OWNERSHIP_RULES[0]?.check(context)).toStrictEqual([]);
  });
});

describe("BS370", () => {
  it("flags transaction=false", () => {
    expect(
      run([
        {
          path: "supabase/schemas/app.sql",
          text: "-- pg-delta: transaction=false\ncreate index concurrently i on t (a);",
        },
      ]),
    ).toMatchObject([{ code: "BS370" }]);
  });

  it("accepts a file without it", () => {
    expect(
      run([{ path: "supabase/schemas/app.sql", text: "select 1;" }]),
    ).toStrictEqual([]);
  });
});

describe("BS371", () => {
  const prelude = `-- better-supabase module: prelude
-- @bsb-block prelude@1 managed

create or replace function better_supabase.actor_may_write() returns boolean language sql as 'select true';
`;

  it("names the prelude when a module file pastes one of its functions", () => {
    const found = run([
      { path: "supabase/schemas/000_prelude.sql", text: prelude },
      {
        path: "supabase/schemas/010_tasks.sql",
        text: MODULE.replace(
          "create table public.tasks (id uuid primary key);",
          "create or replace function better_supabase.actor_may_write() returns boolean language sql as 'select false';",
        ),
      },
    ]);

    expect(found).toMatchObject([{ code: "BS371" }]);
    expect(found[0]?.message).toContain("belongs to the prelude");
  });

  it("flags a policy two app files both create", () => {
    const policy =
      "create policy p on public.notes for select to authenticated using (true);";

    const found = run([
      { path: "supabase/schemas/a.sql", text: policy },
      { path: "supabase/schemas/b.sql", text: policy },
    ]);

    expect(found).toMatchObject([{ code: "BS371" }]);
    expect(found[0]?.message).toContain("policy public.notes.p");
  });

  it("leaves one file's repeated create or replace, extensions and BS369's cases", () => {
    expect(
      run([
        {
          path: "supabase/schemas/a.sql",
          text: "create extension pgcrypto;\ncreate or replace function public.f() returns int language sql as 'select 1';\ncreate or replace function public.f() returns int language sql as 'select 2';",
        },
        { path: "supabase/schemas/b.sql", text: "create extension pgcrypto;" },
        { path: "supabase/schemas/010_tasks.sql", text: MODULE },
        {
          path: "supabase/schemas/app.sql",
          text: "create table public.tasks (id uuid primary key);",
        },
      ]).filter((finding) => finding.code === "BS371"),
    ).toStrictEqual([]);
  });

  it("reports an object two block modules declare", () => {
    const share = (name: string) =>
      `-- @bsb-block ${name}@1 managed\n\ncreate or replace function better_supabase.drive_node_json(node uuid) returns jsonb language sql as 'select 1';`;

    expect(
      run([
        { path: "supabase/schemas/a.sql", text: share("drive-core") },
        { path: "supabase/schemas/b.sql", text: share("drive-files") },
      ]).filter((finding) => finding.code === "BS371"),
    ).toMatchObject([{ code: "BS371" }]);
  });
});

describe("BS372 and BS373", () => {
  const app = (text: string) => [{ path: "supabase/schemas/app.sql", text }];

  it("flags a do block that creates objects, with its line", () => {
    const found = run(
      app("select 1;\ndo $$ begin create table x (id int); end $$;"),
    );

    expect(found).toMatchObject([{ code: "BS372" }]);
    expect(found[0]?.message).toContain("app.sql:2");
  });

  it("accepts a do block that only raises", () => {
    expect(run(app("do $$ begin raise notice 'hi'; end $$;"))).toStrictEqual(
      [],
    );
  });

  it("flags if not exists on a table and an index", () => {
    const found = run(
      app(
        "create table if not exists public.a (id int);\ncreate index if not exists a_idx on public.a (id);\ncreate schema if not exists s;",
      ),
    );

    expect(found.map((finding) => finding.code)).toEqual(["BS373", "BS373"]);
  });

  it("leaves the block modules to the generator", () => {
    expect(
      run([
        {
          path: "supabase/schemas/010_tasks.sql",
          text: `${MODULE}\ncreate table if not exists public.x (id int);\ndo $$ begin create table y (id int); end $$;`,
        },
      ]),
    ).toStrictEqual([]);
  });
});

describe("BS374", () => {
  it("flags a top-level insert in a block module file only", () => {
    const found = run([
      {
        path: "supabase/schemas/010_tasks.sql",
        text: `${MODULE}\ninsert into public.tasks (id) values (gen_random_uuid());`,
      },
      {
        path: "supabase/schemas/app.sql",
        text: "insert into public.notes (id) values (1);",
      },
    ]);

    expect(found).toMatchObject([{ code: "BS374" }]);
    expect(found[0]?.message).toContain("010_tasks.sql");
  });
});

describe("BS375", () => {
  const policy = (name: string, using = "(select auth.uid()) = user_id") =>
    `create policy ${name} on public.notes for select to authenticated using (${using});`;

  it("flags two policies that decide the same way", () => {
    const found = run([
      {
        path: "supabase/schemas/notes.sql",
        text: `${policy("notes_read")}\n${policy("notes_select_own")}`,
      },
    ]).filter((entry) => entry.code === "BS375");

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("notes_read and notes_select_own");
  });

  it("accepts policies that differ in command, roles or expression", () => {
    expect(
      run([
        {
          path: "supabase/schemas/notes.sql",
          text: `${policy("a")}\n${policy("b", "true")}\ncreate policy c on public.notes for select to anon using ((select auth.uid()) = user_id);`,
        },
      ]).filter((entry) => entry.code === "BS375"),
    ).toEqual([]);
  });
});

describe("BS376 and BS377", () => {
  const pgDelta = { database: { sql: { workflow: "pg-delta" as const } } };

  const migration = (text: string) => ({
    path: "supabase/migrations/20260101000000_init.sql",
    text,
  });

  const only = (files: Parameters<typeof run>[0], code: string) =>
    run(files, pgDelta).filter((entry) => entry.code === code);

  it("flags a migration object that no schema file declares", () => {
    const found = only(
      [
        migration(
          'create table "public"."legacy" (id int);\ncreate table "public"."kept" (id int);',
        ),
        {
          path: "supabase/schemas/kept.sql",
          text: "create table public.kept (id int);",
        },
      ],
      "BS376",
    );

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("public.legacy");
  });

  it("lets a dropped table and a managed schema through", () => {
    expect(
      only(
        [
          migration(
            'create table "public"."old" (id int);\ndrop table "public"."old";\ncreate table "auth"."extra" (id int);',
          ),
        ],
        "BS376",
      ),
    ).toEqual([]);
  });

  it("flags a schema object that no migration creates", () => {
    const found = only(
      [
        migration('create table "public"."kept" (id int);'),
        {
          path: "supabase/schemas/all.sql",
          text: "create table public.kept (id int);\ncreate table public.fresh (id int);",
        },
      ],
      "BS377",
    );

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("public.fresh");
  });

  it("follows a rename and reports nothing when a migration has a do block", () => {
    const renamed = [
      migration(
        'create table "public"."old" (id int);\nalter table "public"."old" rename to "fresh";',
      ),
      {
        path: "supabase/schemas/fresh.sql",
        text: "create table public.fresh (id int);",
      },
    ];

    expect(only(renamed, "BS376")).toEqual([]);
    expect(only(renamed, "BS377")).toEqual([]);

    expect(
      only(
        [
          migration(
            "create table public.legacy (id int);\ndo $$ begin perform 1; end; $$;",
          ),
        ],
        "BS376",
      ),
    ).toEqual([]);
  });

  it("reads nothing under the migrations workflow", () => {
    expect(
      run([migration('create table "public"."legacy" (id int);')]).filter(
        (entry) => ["BS376", "BS377"].includes(entry.code),
      ),
    ).toEqual([]);
  });
});

describe("BS378", () => {
  const view = "create view public.v as select id from public.tasks;";

  it("flags a before or after trigger on a view", () => {
    const found = run([
      { path: "supabase/schemas/app.sql", text: MODULE },
      {
        path: "supabase/schemas/views.sql",
        text: `${view}\ncreate trigger t before insert on public.v for each row execute function public.touch();`,
      },
    ]).filter((finding) => finding.code === "BS378");

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("public.v");
  });

  it("accepts an instead of trigger and a trigger on a table", () => {
    expect(
      run([
        { path: "supabase/schemas/app.sql", text: MODULE },
        {
          path: "supabase/schemas/views.sql",
          text: `${view}\ncreate trigger a instead of insert on public.v for each row execute function public.touch();\ncreate trigger b before insert on public.tasks for each row execute function public.touch();`,
        },
      ]).filter((finding) => finding.code === "BS378"),
    ).toStrictEqual([]);
  });
});

describe("BS380", () => {
  const check = (expression: string) =>
    run([
      {
        path: "supabase/schemas/app.sql",
        text: `create table public.t (a int, b int, constraint c check (${expression}));`,
      },
    ]).filter((finding) => finding.code === "BS380");

  it("flags a between joined to another condition", () => {
    expect(check("a between 1 and 5 and b > 0")).toHaveLength(1);
    expect(check("b > 0 or a between 1 and 5")).toHaveLength(1);
  });

  it("accepts a lone between and plain comparisons", () => {
    expect(check("a between 1 and 5")).toStrictEqual([]);
    expect(check("a >= 1 and a <= 5 and b > 0")).toStrictEqual([]);
  });
});
