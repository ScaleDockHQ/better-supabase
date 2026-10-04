import { readFile } from "node:fs/promises";
import { Client, type QueryArrayResult } from "pg";
import { describe, expect, it } from "vitest";

import { dbUrl, reachable } from "./stack.ts";

const live = await reachable();

describe.skipIf(!live)("PermDock policy shapes (pgTAP)", () => {
  it("passes every assertion in permitted-scopes.test.sql", async () => {
    const file = await readFile(
      new URL("../supabase/permitted-scopes.test.sql", import.meta.url),
      "utf8",
    );
    // The file rolls back its own transaction, extension included.
    const text = file.replace(
      /^begin;$/m,
      "begin;\ncreate extension if not exists pgtap with schema extensions;",
    );
    const client = new Client({ connectionString: dbUrl });
    await client.connect();
    try {
      const result: QueryArrayResult | QueryArrayResult[] = await client.query({
        text,
        rowMode: "array",
      });
      const tap = (Array.isArray(result) ? result : [result])
        .flatMap((step) => step.rows.flat())
        .map(String);
      const plan = tap.find((line) => /^1\.\.\d+$/.test(line));
      expect(plan).toBeDefined();
      expect(tap.filter((line) => /^(not ok|# Looks like)/.test(line))).toEqual(
        [],
      );
      expect(tap.filter((line) => /^ok \d+/.test(line))).toHaveLength(
        Number(plan?.slice(3)),
      );
    } finally {
      await client.end();
    }
  });
});
