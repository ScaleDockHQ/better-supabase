import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  migrationHolds,
  migrationModules,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writeLatestMigration,
} from "../../../src/cli/sql/module-migration.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleLayout, renderBlocks } from "../../../src/sql/index.ts";

const config = resolveConfig(
  { database: { sql: { workflow: "migrations" } } },
  "/p",
);

const files = renderBlocks(
  ["memberships", "jsonb-schemas"],
  moduleLayout(config),
);

describe("renderModuleMigration", () => {
  it("orders the extensions, upgrade steps, schema bodies, topics and data", () => {
    const text = renderModuleMigration({
      files,
      upgrade: ["-- step one\nselect 1;"],
      topics: "-- topics\n",
    });

    const order = [
      "-- better-supabase sql: the SQL modules",
      'create extension if not exists "pg_jsonschema"',
      "-- @bsb-upgrade-start",
      "-- step one",
      "-- @bsb-upgrade-end",
      "-- @bsb-block memberships@",
      "-- topics",
      "-- @bsb-block-data memberships",
    ].map((line) => text.indexOf(line));

    expect(order.every((index) => index >= 0)).toBe(true);
    expect(order).toEqual(order.toSorted((a, b) => a - b));
    expect(text.endsWith("\n")).toBe(true);
    expect(text.endsWith("\n\n")).toBe(false);
  });

  it("names the topic policies when no module is installed", () => {
    expect(renderModuleMigration({ files: [], topics: "select 1;" })).toMatch(
      /^-- better-supabase sql: the realtime topic policies, in one migration/,
    );
  });
});

describe("sameModuleMigration and migrationHolds", () => {
  const plain = renderModuleMigration({ files });

  it("ignores the upgrade steps and the package version", () => {
    const upgraded = renderModuleMigration({ files, upgrade: ["select 1;"] });

    expect(sameModuleMigration(upgraded, plain)).toBe(true);

    const older = plain.replace(
      /^(-- better-supabase module: [^\n(]*?)$/m,
      "$1 (0.0.1)",
    );

    expect(older).not.toBe(plain);
    expect(sameModuleMigration(older, plain)).toBe(true);
    expect(sameModuleMigration(undefined, plain)).toBe(false);
    expect(sameModuleMigration(`${plain}select 2;\n`, plain)).toBe(false);
  });

  it("finds one module's file in the migration", () => {
    for (const file of files) {
      expect(migrationHolds(plain, file.contents)).toBe(true);
    }

    expect(migrationHolds(plain, "create table nope ();")).toBe(false);
  });

  it("reads the installed modules and versions", () => {
    expect(
      migrationModules(
        plain.replace("@bsb-block memberships@3", "@bsb-block memberships@1"),
      ).get("memberships"),
    ).toBe(1);
    expect(migrationModules("").size).toBe(0);
  });
});

describe("writeLatestMigration", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-module-migration-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("writes a new migration only when the statements change, or when forced", async () => {
    const project = resolveConfig(
      { database: { sql: { workflow: "migrations" } } },
      root,
    );

    const now = new Date("2026-01-02T03:04:05Z");

    const write = (contents: string, force = false) =>
      writeLatestMigration(project, MODULES_SUFFIX, contents, {
        now,
        dryRun: false,
        force,
      });

    expect(
      await writeLatestMigration(project, MODULES_SUFFIX, "select 1;\n", {
        now,
        dryRun: true,
      }),
    ).toMatchObject({
      wrote: false,
      line: expect.stringMatching(/^Would create /),
    });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/20260102030405_init.sql"),
      "",
    );

    const first = await write("select 1;\n");
    expect(first).toMatchObject({
      wrote: true,
      path: `supabase/migrations/20260102030406${MODULES_SUFFIX}`,
    });
    expect((await write("select 1;\n")).wrote).toBe(false);
    expect((await write("select 1;\n", true)).wrote).toBe(true);
    expect((await write("select 2;\n")).wrote).toBe(true);
    expect(
      (await readdir(join(root, "supabase/migrations"))).filter((name) =>
        name.endsWith(MODULES_SUFFIX),
      ),
    ).toHaveLength(3);
  });
});
