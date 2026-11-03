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
});
