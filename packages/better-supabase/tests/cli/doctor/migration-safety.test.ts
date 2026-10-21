import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import {
  MIGRATION_SAFETY_RULES,
  migrationVersion,
  unappliedMigrations,
} from "../../../src/cli/doctor/migration-safety.ts";
import { RULE_CODES } from "../../../src/cli/doctor/rules.ts";
import { splitStatements } from "../../../src/cli/doctor/shared.ts";

const migration = (version: string, text: string): TextFile => ({
  path: `supabase/migrations/${version}_change.sql`,
  text,
});

const context = (
  files: readonly TextFile[],
  extra: Partial<{
    since: string;
    applied: readonly string[];
  }> = {},
): DoctorContext =>
  // SAFETY: the rules read only these fields of the context.
  ({
    config: {
      doctor:
        extra.since === undefined
          ? {}
          : { migrationSafety: { since: extra.since } },
    },
    configToml: undefined,
    sqlFiles: files,
    ...(extra.applied === undefined
      ? {}
      : {
          database: {
            describe: "test",
            session: true,
            query: async () =>
              extra.applied?.map((version) => ({ version })) ?? [],
          },
        }),
  }) as unknown as DoctorContext;

const run = async (
  code: string,
  files: readonly TextFile[],
  extra?: Parameters<typeof context>[1],
): Promise<string[]> => {
  const rule = MIGRATION_SAFETY_RULES.find((each) => each.code === code);

  return (await rule!.check(context(files, extra))).map(
    (finding) => finding.message,
  );
};

describe("splitStatements", () => {
  it("splits at semicolons outside quotes, dollar quotes and comments", () => {
    expect(
      splitStatements(
        [
          "-- a comment; with a semicolon",
          "create table a (x text default 'a;b');",
          "/* block; /* nested; */ */",
          "create function f() returns void language plpgsql as $body$",
          "begin perform 1; end;",
          "$body$;",
          'select ";" as "x;y"',
        ].join("\n"),
      ),
    ).toEqual([
      { text: "create table a (x text default 'a;b')", line: 2 },
      {
        text: "create function f() returns void language plpgsql as $body$\nbegin perform 1; end;\n$body$",
        line: 4,
      },
      { text: 'select ";" as "x;y"', line: 7 },
    ]);
  });
});

describe("migration safety", () => {
  it("registers BS229 to BS235", () => {
    for (const code of [
      "BS229",
      "BS230",
      "BS231",
      "BS232",
      "BS233",
      "BS234",
      "BS235",
    ]) {
      expect(RULE_CODES).toContain(code);
    }
  });

  it("BS229 flags an index without concurrently on a table the file didn't create", async () => {
    const files = [
      migration(
        "20260101000000",
        [
          "create table tasks (id uuid primary key, title text);",
          "create index tasks_title_idx on tasks (title);",
          "create index projects_name_idx on public.projects (name);",
          "create index concurrently projects_slug_idx on projects (slug);",
        ].join("\n"),
      ),
    ];

    expect(await run("BS229", files)).toEqual([
      expect.stringContaining(":3: creates an index on public.projects"),
    ]);
  });

  it("BS230 flags a foreign key or check without not valid", async () => {
    const files = [
      migration(
        "20260101000000",
        [
          "alter table tasks add constraint tasks_project_fkey foreign key (project_id) references projects (id);",
          "alter table tasks add constraint tasks_points check (points > 0) not valid;",
          "alter table tasks validate constraint tasks_points;",
        ].join("\n"),
      ),
    ];

    expect(await run("BS230", files)).toEqual([
      expect.stringContaining("adds a foreign key to public.tasks"),
    ]);
  });

  it("BS231 flags type changes and set not null without a validated check", async () => {
    const files = [
      migration(
        "20260101000000",
        [
          "alter table tasks alter column points type bigint;",
          "alter table tasks alter column title set not null;",
          "alter table notes add constraint body_set check (body is not null) not valid;",
          "alter table notes validate constraint body_set;",
          "alter table notes alter column body set not null;",
        ].join("\n"),
      ),
    ];

    expect(await run("BS231", files)).toEqual([
      expect.stringContaining("changes a column type of public.tasks"),
      expect.stringContaining("sets not null on a column of public.tasks"),
    ]);
  });

  it("BS232 flags a volatile default on an existing table", async () => {
    const files = [
      migration(
        "20260101000000",
        [
          "alter table tasks add column token uuid default gen_random_uuid();",
          "alter table tasks add column created_at timestamptz default now();",
        ].join("\n"),
      ),
    ];

    expect(await run("BS232", files)).toEqual([
      expect.stringContaining("volatile default (gen_random_uuid())"),
    ]);
  });

  it("BS233 asks for lock_timeout before the first exclusive lock", async () => {
    expect(
      await run("BS233", [
        migration("20260101000000", "alter table tasks add column due date;"),
      ]),
    ).toEqual([expect.stringContaining("without setting lock_timeout")]);

    expect(
      await run("BS233", [
        migration(
          "20260101000000",
          "set lock_timeout = '5s';\nalter table tasks add column due date;",
        ),
      ]),
    ).toEqual([]);

    expect(
      await run("BS233", [
        migration(
          "20260101000000",
          "create table t (id int);\nalter table t enable row level security;",
        ),
      ]),
    ).toEqual([]);
  });

  it("BS234 reports drops and renames as info", async () => {
    const files = [
      migration(
        "20260101000000",
        [
          "drop table old_things;",
          "alter table tasks drop column notes;",
          "alter table tasks rename column title to name;",
          "alter table tasks alter column due drop default;",
          "alter table tasks rename constraint a to b;",
        ].join("\n"),
      ),
    ];

    expect(await run("BS234", files)).toEqual([
      expect.stringContaining("drops a table"),
      expect.stringContaining("drops a column of public.tasks"),
      expect.stringContaining("renames public.tasks"),
    ]);
  });

  it("BS235 flags a better_supabase function dropped without the same signature", async () => {
    const files = [
      migration(
        "20260101000000",
        [
          "drop function if exists better_supabase.audit(regclass, text[], text[], text, text, text, text, text, text);",
          "create or replace function better_supabase.audit(target regclass, ignore text[] default '{}', redact text[] default '{}', key_columns text[] default null, category text default null, event_prefix text default null, target_type text default null, tenant_column text default null, label_column text default null, tenant_path text default null, tenant_function text default null) returns void language sql as $$ select 1 $$;",
          'drop function "better_supabase"."purge"(interval);',
          "drop function better_supabase.set_actor();",
          "create function better_supabase.set_actor() returns trigger language plpgsql as $$ begin return new; end $$;",
          "drop function public.mine(numeric(10, 2), out total int);",
          "drop function better_supabase.pick(numeric(10, 2), out total int);",
          "create function better_supabase.pick(value numeric(10, 2), out total int, out rest int) language sql as $$ select 1, 2 $$;",
        ].join("\n"),
      ),
    ];

    expect(await run("BS235", files)).toEqual([
      expect.stringContaining(":1: drops better_supabase.audit"),
      expect.stringContaining(":3: drops better_supabase.purge"),
    ]);
  });

  it("checks only the newest migration offline without since", async () => {
    const files = [
      migration("20260101000000", "alter table a add column x int;"),
      migration("20260201000000", "alter table b add column y int;"),
    ];

    expect(
      (await unappliedMigrations(context(files))).map((file) => file.path),
    ).toEqual(["supabase/migrations/20260201000000_change.sql"]);
  });

  it("checks the migrations after since, or the ones the database hasn't applied", async () => {
    const files = [
      migration("20260101000000", ""),
      migration("20260201000000", ""),
      migration("20260301000000", ""),
    ];

    expect(
      (
        await unappliedMigrations(
          context(files, { since: "20260101000000_change.sql" }),
        )
      ).map((file) => migrationVersion(file.path)),
    ).toEqual(["20260201000000", "20260301000000"]);

    expect(
      (
        await unappliedMigrations(
          context(files, { applied: ["20260101000000", "20260301000000"] }),
        )
      ).map((file) => migrationVersion(file.path)),
    ).toEqual(["20260201000000"]);
  });
});
