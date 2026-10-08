import { createTestSuite } from "@workflow/world-testing";
import { env } from "node:process";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { beforeAll, describe } from "vitest";

import { dbUrl, reachable } from "./block-session.ts";
import { installWorld } from "./workflow-world.ts";

const live = await reachable();

// The suite spawns a server that loads the world from WORKFLOW_TARGET_WORLD
// and reads its options from the environment it inherits.
env["WORKFLOW_DELIVERY"] = "poll";
env["WORKFLOW_POSTGRES_URL"] ??= dbUrl;

describe.skipIf(!live)("@workflow/world-testing in poll mode", () => {
  beforeAll(async () => {
    const pool = new Pool({ connectionString: dbUrl });
    try {
      await installWorld(pool);
    } finally {
      await pool.end();
    }
  });

  createTestSuite(
    fileURLToPath(
      new URL("../../src/workflow-sdk/world/index.ts", import.meta.url),
    ),
  );
});
