import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { PgQueryable } from "../../../src/cli/db.ts";

import {
  dbVerifyCommand,
  runVerify,
} from "../../../src/cli/commands/verify.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

const LOCAL = { DATABASE_URL: "postgresql://postgres@127.0.0.1:5432/postgres" };

const args = (argv: string[]) => parseCommandArgs(dbVerifyCommand, argv);

function dbWith(catalog: unknown): PgQueryable {
  return {
    // SAFETY: the only query is the catalog query, which answers one row.
    query: (() =>
      Promise.resolve({
        rows: [{ catalog }],
      })) as unknown as PgQueryable["query"],
  };
}

const exposed = {
  tables: [
    {
      schema: "public",
      name: "notes",
      rls: false,
      force: false,
      grants: [{ grantee: "anon", privilege: "SELECT" }],
      policies: [],
    },
  ],
  functions: [],
};

describe("db verify", () => {
  it("reports an exposed table and exits 1", async () => {
    const { connect } = fakeConnect(dbWith(exposed));
    const config = resolveConfig({}, "/tmp/verify");

    const result = await runVerify(config, args([]), LOCAL, { open: connect });

    expect(result.code).toBe(1);
    expect(JSON.stringify(result)).toContain("public.notes");
  });

  it("is clean for an empty catalog and writes one file per persona", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-verify-"));

    try {
      const { connect } = fakeConnect(dbWith({ tables: [], functions: [] }));
      const config = resolveConfig({}, root);

      const result = await runVerify(config, args(["--write-tests"]), LOCAL, {
        open: connect,
      });

      expect(result.code).toBe(0);

      const files = await readdir(join(root, "supabase/tests/database"));

      expect(files).toContain("access_matrix_anon.test.sql");
      expect(files).toHaveLength(6);
      expect(
        await readFile(
          join(root, "supabase/tests/database/access_matrix_anon.test.sql"),
          "utf-8",
        ),
      ).toContain("begin;");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
