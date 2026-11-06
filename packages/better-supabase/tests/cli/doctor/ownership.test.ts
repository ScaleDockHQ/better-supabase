import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { OWNERSHIP_RULES } from "../../../src/cli/doctor/ownership.ts";

const MODULE = `-- better-supabase module: tasks
-- @bsb-block tasks@1 managed

create table public.tasks (id uuid primary key);
create or replace function public.touch() returns void language sql as 'select 1';
`;

const run = (
  files: readonly { path: string; text: string }[],
): { code: string; message: string }[] => {
  // SAFETY: the rules read only `sqlFiles`.
  const context = { sqlFiles: files } as unknown as DoctorContext;

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
      ]),
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
