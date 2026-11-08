import { run } from "better-supabase/cli";
import { appendFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, ROOT } from "./fixture.ts";

// The snapshot stands in for a database, so these tests need no stack.
const OWNERSHIP =
  "BS369,BS370,BS371,BS372,BS373,BS374,BS375,BS376,BS377,BS378,BS380,BS622";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

interface Report {
  readonly data: {
    readonly findings: readonly {
      readonly code: string;
      readonly severity: string;
    }[];
  };
}

const doctor = async (
  dir: string,
  only: string | undefined,
): Promise<{ code: number; codes: string[] }> => {
  const result = await run([
    "doctor",
    "--json",
    ...(only === undefined
      ? ["--ignore", "BS303,BS700,BS701"]
      : ["--only", only]),
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
      ...new Set(
        data.findings
          .filter((finding) => finding.severity !== "info")
          .map((finding) => finding.code),
      ),
    ].toSorted(),
  };
};

const seeded = async (
  files: Readonly<Record<string, string>>,
): Promise<{ code: number; codes: string[] }> => {
  const dir = await copyFixture();

  dirs.push(dir);

  for (const [name, sql] of Object.entries(files)) {
    await appendFile(join(dir, "supabase/schemas", name), `\n${sql}\n`);
  }

  return doctor(dir, OWNERSHIP);
};

const TIMEOUT = 60_000;

describe("doctor on the lienlink fixture", () => {
  it(
    "reports nothing above info on the committed app",
    { timeout: TIMEOUT },
    async () => {
      expect(await doctor(ROOT, undefined)).toStrictEqual({
        code: 0,
        codes: [],
      });
    },
  );

  it(
    "fails on a before trigger aimed at a projection view",
    { timeout: TIMEOUT },
    async () => {
      expect(
        await seeded({
          "030_projections.sql":
            "create trigger teams_touch before update on public.teams for each row execute function public.jobs_audit();",
        }),
      ).toStrictEqual({ code: 1, codes: ["BS378"] });
    },
  );

  it(
    "fails on a view the app and a module both define",
    { timeout: TIMEOUT },
    async () => {
      const found = await seeded({
        "900_better_supabase_001_updated_at.sql":
          "create view public.module_view as select 1 as one;",
        "030_projections.sql":
          "create view public.module_view as select 2 as one;",
      });

      expect(found.code).toBe(1);
      expect(found.codes).toContain("BS369");
    },
  );

  it(
    "fails on a nested between, a do block and a duplicate policy",
    { timeout: TIMEOUT },
    async () => {
      expect(
        await seeded({
          "020_block_alters.sql":
            "alter table better_supabase.teams add constraint teams_slug_length check (length(slug) between 1 and 40 and status = 'active');",
        }),
      ).toStrictEqual({ code: 1, codes: ["BS380"] });
      expect(
        await seeded({
          "050_auth_triggers.sql":
            "do $$ begin execute 'create index jobs_title_idx on public.jobs (title)'; end $$;",
        }),
      ).toStrictEqual({ code: 1, codes: ["BS372"] });
      expect(
        await seeded({
          "010_app.sql":
            "create policy jobs_member_select_again on public.jobs for select to authenticated using (organization_id in (select better_supabase.member_organization_ids()));",
        }),
      ).toStrictEqual({ code: 1, codes: ["BS375"] });
    },
  );
});
