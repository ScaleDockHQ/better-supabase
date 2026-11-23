import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const broken = {
  path: "supabase/schemas/020_broken.sql",
  text: "create table public.a (id uuid primary key);\n\ncreate tabel public.b (id uuid);\n",
};

const context = (root: string): DoctorContext => ({
  config: resolveConfig({}, root),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [
    {
      path: "supabase/schemas/010_ok.sql",
      text: "create table public.ok (id int);",
    },
    broken,
  ],
});

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS731"),
  );

describe("BS731", () => {
  it("names the file, line, column and the default grammar", async () => {
    const root = await mkdtemp(join(tmpdir(), "bs731-"));
    const findings = await run(context(root));

    expect(findings).toEqual([
      expect.objectContaining({
        code: "BS731",
        severity: "warning",
        target: broken.path,
        location: { file: broken.path, line: 3 },
        message: expect.stringMatching(
          /^supabase\/schemas\/020_broken\.sql:3:\d+ does not parse with the Postgres 17 grammar: /u,
        ),
      }),
    ]);
  });

  it("names the grammar of db.major_version", async () => {
    const root = await mkdtemp(join(tmpdir(), "bs731-"));

    await mkdir(join(root, "supabase"));
    await writeFile(
      join(root, "supabase", "config.toml"),
      "[db]\nmajor_version = 15\n",
    );

    const findings = await run(context(root));

    expect(findings[0]?.message).toContain("with the Postgres 15 grammar");
  });
});
