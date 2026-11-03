import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { WORLD_POSTGRES_MIGRATIONS } from "../../../src/sql/modules/workflow-sdk-world-ddl.generated.ts";
import {
  assertWorldMigrations,
  compareMigrations,
} from "../../../src/workflow-sdk/world/drift.ts";

describe("compareMigrations", () => {
  it("accepts the migrations the DDL was generated from", () => {
    expect(compareMigrations(WORLD_POSTGRES_MIGRATIONS)).toBeUndefined();
  });

  it("names new, missing and changed migrations", () => {
    const [first, ...rest] = WORLD_POSTGRES_MIGRATIONS;

    expect(
      compareMigrations([
        { tag: first!.tag, sha256: "0".repeat(64) },
        ...rest.slice(1),
        { tag: "9999_new", sha256: "1" },
      ]),
    ).toEqual({
      added: ["9999_new"],
      removed: [rest[0]!.tag],
      changed: [first!.tag],
    });
  });
});

describe("assertWorldMigrations", () => {
  it("passes for the installed @workflow/world-postgres", async () => {
    await expect(assertWorldMigrations()).resolves.toBeUndefined();
  });

  async function folder(entries: unknown, files: Record<string, string> = {}) {
    const dir = await mkdtemp(join(tmpdir(), "world-migrations-"));

    await mkdir(join(dir, "meta"));
    await writeFile(
      join(dir, "meta", "_journal.json"),
      JSON.stringify({ entries }),
    );

    for (const [name, sql] of Object.entries(files)) {
      await writeFile(join(dir, name), sql);
    }

    return dir;
  }

  it("names the migrations that differ", async () => {
    const dir = await folder([{ tag: "9999_new" }], {
      "9999_new.sql": "select 1;",
    });

    await expect(assertWorldMigrations(dir)).rejects.toThrow(
      /new 9999_new, missing/,
    );
  });

  it("skips the check when the journal is unreadable or malformed", async () => {
    await expect(
      assertWorldMigrations(await folder({})),
    ).resolves.toBeUndefined();

    await expect(
      assertWorldMigrations(await folder([{}])),
    ).resolves.toBeUndefined();

    await expect(
      assertWorldMigrations(await folder([{ tag: "missing" }])),
    ).resolves.toBeUndefined();
  });
});
