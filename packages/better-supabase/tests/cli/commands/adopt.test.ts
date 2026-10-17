import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { ExistingTable } from "../../../src/cli/sql/adopt.ts";

import { runAdopt } from "../../../src/cli/commands/adopt.ts";
import { runApply } from "../../../src/cli/commands/apply.ts";
import { loadConfig } from "../../../src/cli/config.ts";
import { run } from "../../../src/cli/run.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { encodePreset } from "../../../src/preset/index.ts";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "better-supabase-adopt-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

const json = (value: unknown): string => `${JSON.stringify(value, null, 2)}\n`;

const now = () => new Date("2026-10-15T12:00:00Z");

const table = (
  name: string,
  columns: readonly string[],
  udt = "uuid",
): ExistingTable => ({
  schema: "public",
  name,
  columns: columns.map((column) => ({ name: column, udt })),
});

const TEAMS = table("teams", [
  "id",
  "organization_id",
  "name",
  "slug",
  "description",
  "status",
  "created_by",
  "created_at",
  "updated_at",
]);

const MEMBERS = table("team_members", [
  "team_id",
  "user_id",
  "organization_id",
  "created_at",
]);

const tables = () => Promise.resolve([TEAMS, MEMBERS]);

const configPath = () => join(dir, "better-supabase.config.json");

const readConfig = async (): Promise<unknown> =>
  JSON.parse(await readFile(configPath(), "utf-8"));

describe("adopt", () => {
  it("writes the proposed entry and shows the mapping and the diff", async () => {
    await writeFile(configPath(), json({ blocks: ["tags"] }));
    const config = resolveConfig({}, dir);

    const dry = await runAdopt(
      config,
      { block: "teams", "dry-run": true },
      { configFile: configPath(), tables },
    );

    expect(dry.code).toBe(0);
    expect(dry.output).toContain("    tenant       organization_id (guessed)");
    expect(dry.output).toContain('+    "teams": {');
    expect(dry.output).toContain("Dry run: nothing written.");
    expect(await readConfig()).toEqual({ blocks: ["tags"] });

    const written = await runAdopt(
      config,
      { block: "teams", from: "public.teams" },
      { configFile: configPath(), tables },
    );

    expect(written.code).toBe(0);
    expect(written.output).toContain("Run `better-supabase sql sync`");
    expect(written.data).toMatchObject({ block: "teams", written: true });
    expect(await readConfig()).toEqual({
      blocks: {
        tags: {},
        teams: {
          mode: "adopt",
          tables: { teams: "public.teams", members: "public.team_members" },
          columns: {
            teams: { tenant: "organization_id" },
            members: { tenant: "organization_id" },
          },
        },
      },
    });

    const again = await runAdopt(
      await loadConfig(dir, configPath()),
      { block: "teams" },
      { configFile: configPath(), tables },
    );

    expect(again.output).toContain("already holds this mapping");
  });

  it("writes nothing and exits 1 when something can't map", async () => {
    await writeFile(configPath(), json({}));

    const result = await runAdopt(
      resolveConfig({}, dir),
      { block: "teams" },
      {
        configFile: configPath(),
        tables: () => Promise.resolve([table("teams", ["id"]), MEMBERS]),
      },
    );

    expect(result.code).toBe(1);
    expect(result.output).toContain(
      "  error  public.teams has no column for teams.tenant",
    );
    expect(result.error).toContain("blocks.teams wasn't written");
    expect(await readConfig()).toEqual({});
  });

  it("asks for a block, prints the entry without a config, and refuses a config it can't edit", async () => {
    const config = resolveConfig({}, dir);
    expect((await runAdopt(config, {}, { tables })).code).toBe(2);
    const loose = await runAdopt(config, { block: "teams" }, { tables });
    expect(loose.code).toBe(0);
    expect(loose.output).toContain(
      "No config file: add this to blocks yourself.",
    );
    const file = join(dir, "better-supabase.config.ts");
    await writeFile(file, "export default config;\n");

    const refused = await runAdopt(
      config,
      { block: "teams" },
      { configFile: file, tables },
    );

    expect(refused.code).toBe(1);
    expect(refused.error).toContain("Set blocks.teams in it yourself.");
  });

  it("reads the tables from a snapshot through the CLI", async () => {
    await writeFile(configPath(), json({}));

    const result = await run([
      "adopt",
      "teams",
      "--snapshot",
      "missing.json",
      "--cwd",
      dir,
    ]);

    expect(result.code).not.toBe(0);
    expect(result.stderr).toContain("Snapshot not found: missing.json");
  });
});

describe("apply --adopt", () => {
  const preset = encodePreset({ scope: "tenant", blocks: ["teams"] });

  it("adopts the blocks with existing tables and keeps the rest managed", async () => {
    await writeFile(configPath(), json({}));

    const result = await runApply(
      resolveConfig({}, dir),
      { preset, only: "blocks", adopt: true },
      {
        configFile: configPath(),
        now,
        tables,
        reload: (root, file) => loadConfig(root, file),
      },
    );

    expect(result.code).toBe(0);
    expect(result.output).toContain("Adopting teams:");
    expect(result.data).toMatchObject({
      written: true,
      adopted: { teams: { mode: "adopt" } },
    });
    expect(await readConfig()).toMatchObject({
      blocks: {
        "updated-at": {},
        tenant: {},
        access: {},
        teams: { mode: "adopt", tables: { teams: "public.teams" } },
      },
    });
    expect(
      existsSync(
        join(dir, "supabase/schemas/900_better_supabase_58_teams.sql"),
      ),
    ).toBe(true);
  });

  it("says when nothing is there to adopt", async () => {
    await writeFile(configPath(), json({}));

    const result = await runApply(
      resolveConfig({}, dir),
      { preset, adopt: true, "dry-run": true },
      { configFile: configPath(), now, tables: () => Promise.resolve([]) },
    );

    expect(result.code).toBe(0);
    expect(result.output).toContain(
      "No existing tables to adopt: every block stays managed.",
    );
  });

  it("writes nothing when a block's existing tables can't be adopted", async () => {
    await writeFile(configPath(), json({}));

    const result = await runApply(
      resolveConfig({}, dir),
      { preset, adopt: true },
      {
        configFile: configPath(),
        now,
        tables: () => Promise.resolve([table("teams", ["id"]), MEMBERS]),
      },
    );

    expect(result.code).toBe(1);
    expect(result.error).toContain("Nothing was written: teams has a table");
    expect(await readConfig()).toEqual({});
  });

  it("refuses --adopt with --only conventions or without tables", async () => {
    const config = resolveConfig({}, dir);
    await writeFile(configPath(), json({}));
    expect(
      (
        await runApply(
          config,
          { preset, adopt: true, only: "conventions" },
          { configFile: configPath(), now, tables },
        )
      ).error,
    ).toBe("--adopt maps blocks, and --only conventions takes none.");
    expect(
      (
        await runApply(
          config,
          { preset, adopt: true },
          { configFile: configPath(), now },
        )
      ).code,
    ).toBe(2);
  });
});
