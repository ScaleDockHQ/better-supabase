import { run } from "better-supabase/cli";
import { appendFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, ROOT } from "./fixture.ts";

// The ownership and coverage rules of doctor, which read the schema files and
// migrations. The snapshot stands in for a database, so the test needs no stack.
const OWNERSHIP =
  "BS369,BS370,BS371,BS372,BS373,BS374,BS375,BS376,BS377,BS378,BS380,BS622";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

interface Report {
  readonly data: { readonly findings: readonly { readonly code: string }[] };
}

const doctor = async (
  dir: string,
): Promise<{ code: number; codes: string[] }> => {
  const result = await run([
    "doctor",
    "--json",
    "--only",
    OWNERSHIP,
    "--fail-on",
    "warning",
    "--snapshot",
    join(dir, "snapshot.json"),
    "--cwd",
    dir,
  ]);

  const { data } = JSON.parse(result.stdout) as Report;

  return {
    code: result.code,
    codes: [
      ...new Set(data.findings.map((finding) => finding.code)),
    ].toSorted(),
  };
};

const seeded = async (
  edit: (
    dir: string,
    app: (name: string, sql: string) => Promise<void>,
  ) => Promise<void>,
): Promise<{ code: number; codes: string[] }> => {
  const dir = await copyFixture();

  dirs.push(dir);
  await edit(dir, (name, sql) =>
    appendFile(join(dir, "supabase/schemas", name), `\n${sql}\n`),
  );

  return doctor(dir);
};

const TIMEOUT = 60_000;

describe("doctor on the declarative fixture", () => {
  it(
    "has no ownership or coverage finding on the committed app",
    { timeout: TIMEOUT },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);

      expect(await doctor(dir)).toStrictEqual({ code: 0, codes: [] });
    },
  );

  it(
    "reports nothing at all on the committed app",
    { timeout: TIMEOUT },
    async () => {
      const result = await run([
        "doctor",
        "--json",
        // BS303 compares generated client code, which this app has none of.
        // BS700 and BS701 report the host's shared memory. BS630 reports
        // memberships.user_id and memberships.invited_by, both keys to
        // auth.users.
        "--ignore",
        "BS303,BS630,BS700,BS701",
        "--fail-on",
        "warning",
        "--snapshot",
        join(ROOT, "snapshot.json"),
        "--cwd",
        ROOT,
      ]);

      const { data } = JSON.parse(result.stdout) as Report;

      expect(
        data.findings.filter(
          (finding) => (finding as { severity?: string }).severity !== "info",
        ),
      ).toStrictEqual([]);
      expect(result.code).toBe(0);
    },
  );

  it(
    "fails on a do block that creates objects",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded((_dir, app) =>
        app(
          "020_app_extensions.sql",
          `do $$ begin execute 'create index projects_name_idx on public.projects (name)'; end $$;`,
        ),
      );

      expect(found).toStrictEqual({ code: 1, codes: ["BS372"] });
    },
  );

  it(
    "fails on an actor_may_write copy in an app file or in a module file",
    { timeout: TIMEOUT },
    async () => {
      const copy = `create or replace function better_supabase.actor_may_write() returns boolean language sql as 'select true';`;

      // The app declares what a module declares.
      expect(
        await seeded((_dir, app) => app("020_app_extensions.sql", copy)),
      ).toStrictEqual({ code: 1, codes: ["BS369"] });
      // A module file from before the prelude repeats a prelude helper.
      expect(
        await seeded((_dir, app) =>
          app("900_better_supabase_001_updated_at.sql", copy),
        ),
      ).toStrictEqual({ code: 1, codes: ["BS371"] });
    },
  );

  it(
    "fails on two policies that decide the same way",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded((_dir, app) =>
        app(
          "020_app_extensions.sql",
          `create policy projects_member_select_again on public.projects for select to authenticated using (organization_id in (select better_supabase.member_organization_ids()));`,
        ),
      );

      expect(found).toStrictEqual({ code: 1, codes: ["BS375"] });
    },
  );

  it(
    "fails on a top-level insert in a module file",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded((_dir, app) =>
        app(
          "900_better_supabase_001_updated_at.sql",
          "insert into public.organizations (name, slug) values ('Seed', 'seed');",
        ),
      );

      expect(found).toStrictEqual({ code: 1, codes: ["BS374"] });
    },
  );

  it("fails on a trigger aimed at a view", { timeout: TIMEOUT }, async () => {
    const found = await seeded((_dir, app) =>
      app(
        "020_app_extensions.sql",
        "create trigger my_organizations_touch before update on public.my_organizations for each row execute function public.projects_reject_archived_rename();",
      ),
    );

    expect(found).toStrictEqual({ code: 1, codes: ["BS378"] });
  });

  it(
    "fails on a view the app and a module both define",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded(async (_dir, app) => {
        await app(
          "900_better_supabase_001_updated_at.sql",
          "create view public.module_view as select 1 as one;",
        );
        await app(
          "020_app_extensions.sql",
          "create view public.module_view as select 2 as one;",
        );
      });

      expect(found.code).toBe(1);
      expect(found.codes).toContain("BS369");
    },
  );

  it(
    "fails on a between nested in a compound check",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded((_dir, app) =>
        app(
          "020_app_extensions.sql",
          "alter table public.projects add constraint projects_name_length check (length(name) between 1 and 80 and archived_at is null);",
        ),
      );

      expect(found).toStrictEqual({ code: 1, codes: ["BS380"] });
    },
  );

  it(
    "fails on a block-added column the app does not declare",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded(async (dir) => {
        await rm(join(dir, "supabase/schemas/profiles.block-columns.sql"));
      });

      expect(found).toStrictEqual({ code: 1, codes: ["BS622"] });
    },
  );

  it(
    "fails on a table a migration creates and no schema file declares",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded(async (dir) => {
        await writeFile(
          join(dir, "supabase/migrations/20261109000000_hand.sql"),
          "create table public.orphans (id uuid primary key);\n",
        );
      });

      expect(found).toStrictEqual({ code: 1, codes: ["BS376"] });
    },
  );

  it(
    "fails on a table a schema file declares and no migration creates",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded((_dir, app) =>
        app(
          "020_app_extensions.sql",
          "create table public.notes (id uuid primary key);",
        ),
      );

      expect(found).toStrictEqual({ code: 1, codes: ["BS377"] });
    },
  );

  it("fails on an if not exists index", { timeout: TIMEOUT }, async () => {
    const found = await seeded((_dir, app) =>
      app(
        "020_app_extensions.sql",
        "create index if not exists projects_created_at_idx on public.projects (created_at);",
      ),
    );

    expect(found).toStrictEqual({ code: 1, codes: ["BS373"] });
  });
});
