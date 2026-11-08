import { parseArgs } from "citty";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runSql } from "../../../src/cli/commands/sql.ts";
import { SQL_ARGS } from "../../../src/cli/sql/args.ts";
import { resolveConfig } from "../../../src/config/index.ts";

vi.mock(import("../../../src/sql/index.ts"), async (original) => ({
  ...(await original()),
  upgradePlan: () => [
    {
      module: "memberships",
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
    root = await mkdtemp(join(tmpdir(), "bsb-sql-upgrade-"));
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-03T08:09:10Z"));
  });
  afterEach(async () => {
    vi.useRealTimers();
    await rm(root, { recursive: true, force: true });
  });

  const sql = (argv: string[]) =>
    runSql(
      resolveConfig({ blocks: ["memberships"] }, root),
      parseArgs(argv, SQL_ARGS),
    );

  it("writes the steps with SQL into a migration before the schema diff", async () => {
    await sql(["sync"]);

    const dry = await sql(["upgrade", "--dry-run"]);

    const path =
      /supabase\/migrations\/20261003080910_better_supabase_reviewed_upgrade_[0-9a-f]{8}\.sql/.exec(
        dry.output ?? "",
      )?.[0];

    expect(path).toBeDefined();
    expect(dry.output).toContain(`Would create ${path!}`);
    await expect(readdir(join(root, "supabase"))).resolves.not.toContain(
      "migrations",
    );

    const done = await sql(["upgrade"]);
    expect(done.code).toBe(0);
    expect(done.output).toContain(`Created ${path!}`);
    expect(done.output).toContain("memberships: version 1 to 3");
    expect(done.output).toContain("  Renames org_id to tenant_id.");
    const migration = await readFile(join(root, path!), "utf-8");
    expect(migration).toContain(
      "-- memberships: version 2 to 3. Renames org_id to tenant_id.\nalter table memberships rename column org_id to tenant_id;",
    );
    expect(migration).not.toContain("Nothing to run.");
  });

  it("marks the pg-delta migration as a reviewed hand migration", async () => {
    await sql(["sync"]);
    await sql(["upgrade"]);

    const name = (await readdir(join(root, "supabase/migrations"))).find(
      (file) => file.includes("_better_supabase_reviewed_upgrade_"),
    );

    const text = await readFile(
      join(root, "supabase/migrations", name!),
      "utf-8",
    );

    expect(text).toContain("-- destructive: reviewed");
    expect(text).toContain("alter table memberships rename column");
  });

  it("writes no schema migration, only the reviewed one", async () => {
    await sql(["sync"]);
    await sql(["upgrade"]);

    const names = await readdir(join(root, "supabase/migrations"));

    expect(
      names.filter((file) => !file.includes("_reviewed_upgrade_")),
    ).toEqual(names.filter((file) => file.includes("_extensions")));
  });

  it("keeps the plain upgrade migration under the migra workflow", async () => {
    await mkdir(join(root, "supabase"), { recursive: true });
    await writeFile(
      join(root, "supabase/config.toml"),
      '[db.migrations]\nschema_paths = ["./schemas/*.sql"]\n',
    );
    await sql(["sync"]);
    await sql(["upgrade"]);

    const names = await readdir(join(root, "supabase/migrations"));

    expect(names.some((file) => file.includes("_block_upgrade_"))).toBe(true);
    expect(names.some((file) => file.includes("_reviewed_upgrade_"))).toBe(
      false,
    );

    const name = names.find((file) => file.includes("_block_upgrade_"))!;

    expect(
      await readFile(join(root, "supabase/migrations", name), "utf-8"),
    ).not.toContain("destructive: reviewed");
  });
});
