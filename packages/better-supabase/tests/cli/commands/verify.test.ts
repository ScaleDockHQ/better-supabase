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
import { CliError } from "../../../src/cli/core/errors.ts";
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

  it("reports a failing query as a failed command", async () => {
    const failing: PgQueryable = {
      // SAFETY: the query rejects.
      query: () => Promise.reject(new Error("no connection")),
    };

    const { connect } = fakeConnect(failing);
    const config = resolveConfig({}, "/tmp/verify");

    const result = await runVerify(config, args([]), LOCAL, { open: connect });

    expect(result).toMatchObject({ code: 1, errorCode: "failed" });
    expect(result.error).toContain("no connection");
  });

  it("counts a single error and a single other finding", async () => {
    const { connect } = fakeConnect(
      dbWith({
        ...exposed,
        functions: [
          {
            schema: "public",
            name: "danger",
            definer: true,
            searchPath: false,
          },
        ],
      }),
    );

    const config = resolveConfig({}, "/tmp/verify");
    const result = await runVerify(config, args([]), LOCAL, { open: connect });

    expect(result.code).toBe(1);
    expect(result.error).toContain("public.danger");
  });

  it("counts several errors and rethrows a CLI error", async () => {
    const two = {
      tables: [...exposed.tables, { ...exposed.tables[0], name: "tasks" }],
      functions: [],
    };

    const config = resolveConfig({}, "/tmp/verify");

    const result = await runVerify(config, args([]), LOCAL, {
      open: fakeConnect(dbWith(two)).connect,
    });

    expect(result.error).toContain("2 errors");

    const refusing: PgQueryable = {
      // SAFETY: the query rejects with a CLI error.
      query: () => Promise.reject(new CliError("not_found", "no schema")),
    };

    await expect(
      runVerify(config, args([]), LOCAL, {
        open: fakeConnect(refusing).connect,
      }),
    ).rejects.toThrow("no schema");
  });

  it("writes the files to --dir", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-verify-dir-"));

    try {
      const config = resolveConfig({}, root);

      const result = await runVerify(
        config,
        args(["--write-tests", "--dir", "tests/pg"]),
        LOCAL,
        { open: fakeConnect(dbWith({ tables: [], functions: [] })).connect },
      );

      expect(result.code).toBe(0);
      expect(await readdir(join(root, "tests/pg"))).toHaveLength(6);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
