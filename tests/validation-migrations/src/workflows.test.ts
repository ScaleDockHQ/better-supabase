import { run } from "better-supabase/cli";
import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import type { Workflow } from "./fixture.ts";

import {
  APP_MIGRATION,
  configText,
  migrationsOf,
  project,
  readTree,
} from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

const fresh = async (
  workflow: Workflow,
  options?: Parameters<typeof project>[1],
): Promise<string> => {
  const dir = await project(workflow, options);

  dirs.push(dir);

  return dir;
};

const upgrade = (dir: string) => run(["upgrade", "--cwd", dir]);

// The first command loads the CLI from source.
const TIMEOUT = 60_000;

// The app's three adopted tables, which a module must never create again.
const APP_TABLES = ["organizations", "memberships", "profiles"] as const;

const createsAppTable = (sql: string): boolean =>
  APP_TABLES.some((name) =>
    new RegExp(
      `create table (if not exists )?("public"\\.)?"?${name}"?\\s*\\(`,
      "i",
    ).test(sql),
  );

describe("the migrations workflow", () => {
  it(
    "writes one content-stamped migration after the newest and touches no schema file",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("migrations");
      const before = await readTree(dir);

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const [app, written, ...rest] = await migrationsOf(dir);

      expect(rest).toStrictEqual([]);
      expect(app).toBe(APP_MIGRATION);
      expect(written).toMatch(
        /^\d{14}_better_supabase_modules_[0-9a-f]{8}\.sql$/,
      );
      // The stamp follows the newest migration even when its date is ahead of now.
      expect((written ?? "") > APP_MIGRATION).toBe(true);

      const after = await readTree(dir);

      expect(
        [...after.keys()].filter((path) => path.includes("schemas")),
      ).toStrictEqual([]);
      expect(after.get(join("supabase/migrations", APP_MIGRATION))).toBe(
        before.get(join("supabase/migrations", APP_MIGRATION)),
      );
    },
  );

  it(
    "emits no app table twice and writes nothing on a second upgrade",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("migrations");

      await upgrade(dir);

      const [, written] = await migrationsOf(dir);

      const text = await readFile(
        join(dir, "supabase/migrations", written ?? ""),
        "utf-8",
      );

      expect(createsAppTable(text)).toBe(false);
      expect(text).toContain("organizations");

      const tree = await readTree(dir);

      expect(await upgrade(dir)).toMatchObject({ code: 0 });
      expect(await readTree(dir)).toStrictEqual(tree);

      expect(await run(["upgrade", "--check", "--cwd", dir])).toMatchObject({
        code: 0,
      });
    },
  );

  it(
    "writes a new migration with a new hash when the config adds a module",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("migrations");

      await upgrade(dir);

      const first = await migrationsOf(dir);

      await writeFile(
        join(dir, "better-supabase.config.ts"),
        configText("migrations", { blocks: ["teams"] }),
      );

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const second = await migrationsOf(dir);

      expect(second).toHaveLength(first.length + 1);
      expect(second.slice(0, first.length)).toStrictEqual(first);

      const [previous, next] = second.slice(-2);

      expect(next).toMatch(/_better_supabase_modules_[0-9a-f]{8}\.sql$/);
      expect((next ?? "") > (previous ?? "")).toBe(true);
      expect(next?.slice(-13)).not.toBe(previous?.slice(-13));
    },
  );
});

describe("the migra workflow", () => {
  it(
    "writes the module files into supabase/schemas and no migration",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("migra");

      expect(await upgrade(dir)).toMatchObject({ code: 0 });
      expect(await migrationsOf(dir)).toStrictEqual([APP_MIGRATION]);

      const tree = await readTree(dir);

      const modules = [...tree].filter(([path]) =>
        /schemas\/900_better_supabase_[^/]*\.sql$/.test(path),
      );

      expect(modules.length).toBeGreaterThan(0);

      for (const [, text] of modules) {
        expect(createsAppTable(text)).toBe(false);
      }
    },
  );

  it(
    "keeps the app's tables in view on a second upgrade",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("migra");

      await upgrade(dir);

      const tree = await readTree(dir);

      expect(await upgrade(dir)).toMatchObject({ code: 0 });
      expect(await readTree(dir)).toStrictEqual(tree);

      // The seed statements are data, so the check reports them until
      // `add --adopt` writes the data migration.
      expect(await run(["upgrade", "--check", "--cwd", dir])).toMatchObject({
        code: 1,
        stderr: expect.stringContaining("in no data migration"),
      });

      expect(await run(["add", "--adopt", "--cwd", dir])).toMatchObject({
        code: 0,
      });

      expect(await run(["upgrade", "--check", "--cwd", dir])).toMatchObject({
        code: 0,
      });
    },
  );
});

describe("the pg-delta workflow", () => {
  it(
    "writes no migration: the schema files are the source",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("pg-delta");

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const tree = await readTree(dir);

      expect([...tree.keys()].some((path) => path.includes("migrations"))).toBe(
        false,
      );
      expect(
        tree.has("supabase/schemas/900_better_supabase_021_organizations.sql"),
      ).toBe(true);
    },
  );
});

describe.each(["migrations", "migra"] as const)(
  "doctor under %s",
  (workflow) => {
    it(
      "finds no ownership or coverage problem after upgrade",
      { timeout: TIMEOUT },
      async () => {
        const dir = await fresh(workflow);

        await upgrade(dir);

        const result = await run([
          "doctor",
          "--json",
          "--only",
          "BS369,BS370,BS371,BS372,BS373,BS374,BS375,BS376,BS377,BS378,BS380,BS622",
          "--fail-on",
          "warning",
          "--snapshot",
          join(dir, "snapshot.json"),
          "--cwd",
          dir,
        ]);

        expect(result).toMatchObject({ code: 0 });
      },
    );
  },
);

describe("a Supabase Lite project", () => {
  it(
    "runs upgrade and doctor with the migrations workflow",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh("migrations", { lite: "pglite" });

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const doctor = await run([
        "doctor",
        "--only",
        "BS369,BS371,BS372,BS375",
        "--snapshot",
        join(dir, "snapshot.json"),
        "--cwd",
        dir,
      ]);

      expect(doctor).toMatchObject({ code: 0 });
    },
  );
});
