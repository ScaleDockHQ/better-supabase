import { describe, expect, it } from "vitest";

import { scanSql } from "../../../src/cli/schema-reader/index.ts";

const large = (name: string): string =>
  `select 1 as ${name};\n`.repeat(110_000);

describe("scanSql", () => {
  // Scans three texts past the 2,000,000 character cache: 15.1 s on a loaded CI shard.
  it(
    "scans a text once while it fits the cache, and again once larger texts pushed it out",
    { timeout: 60_000 },
    async () => {
      const first = large("first");
      const held = await scanSql(first, { majorVersion: 16 });

      expect(await scanSql(first, { majorVersion: 16 })).toBe(held);

      await scanSql(large("second"), { majorVersion: 17 });

      const again = await scanSql(first, { majorVersion: 16 });

      expect(again).not.toBe(held);
      expect(again).toEqual(held);
    },
  );
});
