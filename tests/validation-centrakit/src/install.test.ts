import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, withCentraKit } from "./stack.ts";

const live = await reachable();

describe.skipIf(!live)("installing on CentraKit", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("installs every SQL module", async () => {
    await withCentraKit(pool, async (s) => {
      expect(await s.value("1")).toBe(1);
    });
  });
});
