import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";

import type { ExistingTable } from "../../../src/cli/sql/adopt.ts";

import { runAdopt } from "../../../src/cli/commands/adopt.ts";
import { runApply } from "../../../src/cli/commands/apply.ts";
import { loadConfig } from "../../../src/cli/config.ts";
import { run } from "../../../src/cli/core/run.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import {
  createUrl,
  presetFromSpec,
  resolvePreset,
} from "../../../src/preset/index.ts";
import { modulePermissionKeys, SQL_MODULES } from "../../../src/sql/index.ts";
import {
  stubProvider,
  withProvider,
} from "../../fixtures/authorization-provider.ts";
import { usageError } from "../fixtures/usage.ts";

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

const ENUM_TEAMS: ExistingTable = {
  ...TEAMS,
  columns: TEAMS.columns.map((column) =>
    column.name === "name"
      ? { name: "name", udt: "team_name", isEnum: true, typeSchema: "public" }
      : column,
  ),
};

const CALENDARS = table("calendars", [
  "id",
  "tenant_id",
  "name",
  "tz",
  "color",
  "owner_type",
  "owner_id",
  "visibility",
  "description",
  "rank",
  "is_default",
  "created_at",
]);

const providerConfig = () =>
  resolveConfig(
    {
      auth: {
        authorization: withProvider({
          permissions: modulePermissionKeys(
            { permissions: { model: "provider" } },
            Object.keys(SQL_MODULES),
          ).map((entry) => ({ key: entry.key, sqlComplete: true })),
          functions: {
            ...stubProvider.functions,
            rowsWith: "authz.rows_{resource}({permission}, {ids})",
            rowsWithFor:
              "authz.rows_{resource}_for({user}, {permission}, {ids})",
          },
        }),
      },
      blocks: {
        permissions: { model: "provider" },
        calendar: {
          options: {
            access: true,
            calendarDetails: true,
            accessFunctions: {
              read: { rows: "agenda_calendar", key: "agendaCalendar.read" },
              write: { rows: "agenda_calendar", key: "agendaCalendar.update" },
            },
          },
        },
      },
    },
    dir,
  );

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
      { block: "teams", tables: "public.teams" },
      { configFile: configPath(), tables },
    );

    expect(written.code).toBe(0);
    expect(written.output).toContain("Run `better-supabase upgrade`");
    expect(written.data).toMatchObject({ block: "teams", written: true });
    expect(await readConfig()).toEqual({
      blocks: {
        tags: {},
        teams: {
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

  it("sets tooling.doctor.migrationSafety.since to the newest migration", async () => {
    await writeFile(configPath(), json({}));
    await mkdir(join(dir, "supabase/migrations"), { recursive: true });
    await writeFile(join(dir, "supabase/migrations/20260101000000_a.sql"), "");
    await writeFile(join(dir, "supabase/migrations/20260301000000_b.sql"), "");

    const written = await runAdopt(
      resolveConfig({}, dir),
      { block: "teams" },
      { configFile: configPath(), tables },
    );

    expect(written.code).toBe(0);
    expect(await readConfig()).toMatchObject({
      tooling: { doctor: { migrationSafety: { since: "20260301000000" } } },
    });
  });

  it("writes nothing and exits 1 when something can't map", async () => {
    await writeFile(configPath(), json({}));

    const result = await runAdopt(
      resolveConfig({}, dir),
      { block: "teams" },
      {
        configFile: configPath(),
        tables: () => Promise.resolve([ENUM_TEAMS, MEMBERS]),
      },
    );

    expect(result.code).toBe(1);
    expect(result.output).toContain(
      "  error  blocks.teams writes text into public.teams.name (teams.name), which is the enum public.team_name.",
    );
    expect(result.error).toContain("blocks.teams wasn't written");
    expect(await readConfig()).toEqual({});
  });

  it("asks for a block, prints the entry without a config, and refuses a config it can't edit", async () => {
    const config = resolveConfig({}, dir);
    await usageError(() => runAdopt(config, {}, { tables }));
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

  it("renders the proposal with the authorization provider's row checks", async () => {
    await writeFile(configPath(), json({}));

    const result = await runAdopt(
      providerConfig(),
      { block: "calendar", tables: "public.calendars", "dry-run": true },
      { configFile: configPath(), tables: () => Promise.resolve([CALENDARS]) },
    );

    expect(result.data).toMatchObject({ errors: [] });
    expect(result.code).toBe(0);
  });

  it("reads the tables from a snapshot through the CLI", async () => {
    await writeFile(configPath(), json({}));

    const result = await run([
      "add",
      "--adopt",
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

describe("add --over", () => {
  it("adopts a block over the named table through the CLI", async () => {
    await writeFile(join(dir, "better-supabase.config.json"), json({}));

    const result = await run([
      "add",
      "teams",
      "--over",
      "public.teams",
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
  let preset: string;

  beforeAll(async () => {
    preset = await createUrl(
      resolvePreset(presetFromSpec({ scope: "tenant", blocks: ["teams"] })),
    );
  });

  it("maps the blocks with existing tables and leaves the rest to create theirs", async () => {
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
      adopted: {
        teams: {
          tables: { teams: "public.teams", members: "public.team_members" },
        },
      },
    });
    expect(await readConfig()).toMatchObject({
      blocks: {
        "updated-at": {},
        memberships: {},
        permissions: {},
        teams: { tables: { teams: "public.teams" } },
      },
    });
    expect(
      existsSync(
        join(dir, "supabase/schemas/900_better_supabase_058_teams.sql"),
      ),
    ).toBe(true);
  });

  it("proposes a block with the authorization provider's row checks", async () => {
    await writeFile(configPath(), json({}));

    const result = await runApply(
      providerConfig(),
      {
        preset: await createUrl(
          resolvePreset(
            presetFromSpec({ scope: "tenant", blocks: ["calendar"] }),
          ),
        ),
        only: "blocks",
        adopt: true,
        "dry-run": true,
      },
      {
        configFile: configPath(),
        now,
        tables: () => Promise.resolve([CALENDARS]),
      },
    );

    expect(result.error).toBeUndefined();
    expect(result.output).toContain("Adopting calendar:");
    expect(result.code).toBe(0);
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
        tables: () => Promise.resolve([ENUM_TEAMS, MEMBERS]),
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
      await usageError(() =>
        runApply(
          config,
          { preset, adopt: true, only: "conventions" },
          { configFile: configPath(), now, tables },
        ),
      ),
    ).toBe("--adopt maps blocks, and --only conventions takes none.");
    await usageError(() =>
      runApply(
        config,
        { preset, adopt: true },
        { configFile: configPath(), now },
      ),
    );
  });
});
