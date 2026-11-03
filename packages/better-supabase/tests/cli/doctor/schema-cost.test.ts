import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import {
  LITERAL_LIMIT,
  MODULE_SQL_LIMIT,
} from "../../../src/cli/doctor/schema-cost.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const context = (sqlFiles: DoctorContext["sqlFiles"]): DoctorContext => ({
  config: resolveConfig({}, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  ...(sqlFiles === undefined ? {} : { sqlFiles }),
});

const run = (code: string, sqlFiles: DoctorContext["sqlFiles"]) =>
  runRules(
    context(sqlFiles),
    RULES.filter((rule) => rule.code === code),
  );

describe("BS243 large literal in a security definer helper", () => {
  const helper = (literal: string, definer = true) =>
    `create or replace function private.perm_map()\nreturns jsonb language sql stable ${definer ? "security definer" : ""}\nas $$ select '${literal}'::jsonb $$;\n`;

  it("flags a literal above 1 KB", async () => {
    const findings = await run("BS243", [
      {
        path: "supabase/schemas/helpers.sql",
        text: helper("x".repeat(LITERAL_LIMIT + 1)),
      },
    ]);

    expect(findings).toMatchObject([
      { code: "BS243", target: "private.perm_map" },
    ]);
    expect(findings[0]!.message).toContain("1025-character literal");
  });

  it("ignores small literals and invoker functions", async () => {
    expect(
      await run("BS243", [
        { path: "a.sql", text: helper("x".repeat(LITERAL_LIMIT)) },
        { path: "b.sql", text: helper("x".repeat(5000), false) },
      ]),
    ).toEqual([]);
  });

  it("reads a tagged dollar-quoted literal", async () => {
    const text = `create function private.f() returns text language sql security definer as $f$ select $q$${"y".repeat(2000)}$q$ $f$;`;

    expect(await run("BS243", [{ path: "c.sql", text }])).toHaveLength(1);
  });
});

describe("BS244 schema cache pressure", () => {
  it("is quiet for a small project", async () => {
    expect(await run("BS244", [])).toEqual([]);
  });

  it("reports oversized module SQL", async () => {
    const findings = await run("BS244", [
      {
        path: "supabase/schemas/modules.sql",
        text: `-- @bsb-block 1\n${"-".repeat(MODULE_SQL_LIMIT)}`,
      },
    ]);

    expect(findings).toMatchObject([{ target: "modules:sql-size" }]);
  });
});
