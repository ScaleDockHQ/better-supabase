import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { parseCommandArgs } from "../../../src/cli/command.ts";
import {
  runSql,
  sqlCommand,
  type SqlArgs,
} from "../../../src/cli/commands/sql.ts";
import { resolveConfig } from "../../../src/config/index.ts";

vi.mock(import("../../../src/sql/index.ts"), async (original) => ({
  ...(await original()),
  upgradePlan: () => [
    {
      module: "tenant",
      from: 1,
      to: 3,
      steps: [
        { from: 1, description: "Nothing to run.", sql: "" },
        {
          from: 2,
          description: "Renames org_id to tenant_id.",
          sql: "alter table memberships rename column org_id to tenant_id;",
        },
      ],
    },
  ],
}));

describe("sql upgrade with forward steps", () => {
  let root: string;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bs-sql-upgrade-"));
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-03T08:09:10Z"));
  });
  afterEach(async () => {
    vi.useRealTimers();
    await rm(root, { recursive: true, force: true });
  });

  const sql = (argv: string[]) =>
    runSql(
      resolveConfig({ sql: { kit: ["tenant"] } }, root),
      // SAFETY: parseCommandArgs returns the declared args of sqlCommand.
      parseCommandArgs(sqlCommand, argv) as SqlArgs,
    );

  it("writes the steps with SQL into a migration before the schema diff", async () => {
    await sql(["sync"]);
    const path =
      "supabase/migrations/20261003080910_better_supabase_kit_upgrade.sql";

    const dry = await sql(["upgrade", "--dry-run"]);
    expect(dry.output).toContain(`Would write ${path}`);
    await expect(readdir(join(root, "supabase"))).resolves.not.toContain(
      "migrations",
    );

    const done = await sql(["upgrade"]);
    expect(done.code).toBe(0);
    expect(done.output).toContain(`Wrote ${path}`);
    expect(done.output).toContain("tenant: version 1 to 3");
    expect(done.output).toContain("  Renames org_id to tenant_id.");
    const migration = await readFile(join(root, path), "utf8");
    expect(migration).toContain(
      "-- tenant: version 2 to 3. Renames org_id to tenant_id.\nalter table memberships rename column org_id to tenant_id;",
    );
    expect(migration).not.toContain("Nothing to run.");
  });
});
