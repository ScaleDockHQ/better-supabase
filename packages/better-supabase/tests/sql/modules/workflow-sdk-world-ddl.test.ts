import { describe, expect, it } from "vitest";

import {
  readMigrations,
  worldPostgresVersion,
} from "../../../scripts/gen-workflow-ddl.ts";
import {
  WORLD_POSTGRES_MIGRATIONS,
  WORLD_POSTGRES_VERSION,
} from "../../../src/sql/modules/workflow-sdk-world-ddl.generated.ts";

describe("workflow-sdk-world DDL", () => {
  it("matches the installed @workflow/world-postgres migrations", async () => {
    expect(await worldPostgresVersion()).toBe(WORLD_POSTGRES_VERSION);
    const installed = await readMigrations();
    expect(installed.map(({ tag, sha256 }) => ({ tag, sha256 }))).toEqual(
      WORLD_POSTGRES_MIGRATIONS,
    );
  });
});
