import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { dbQueryCommand, runDbQuery } from "../../../src/cli/commands/db.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

describe("db query", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-db-"));
    await writeFile(join(root, "a.sql"), "select 1; select 2;");
    await writeFile(join(root, "b.sql"), "select 3;");
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  function run(
    argv: string[],
    fail?: string,
  ): { done: ReturnType<typeof runDbQuery>; sent: string[] } {
    const sent: string[] = [];

    const open = fakeConnect({
      query: (text: string) => {
        sent.push(text);

        return text === fail
          ? Promise.reject(new Error("boom"))
          : Promise.resolve({ rows: [] });
      },
    });

    const done = runDbQuery(
      resolveConfig({}, root),
      parseCommandArgs(dbQueryCommand, argv),
      { DATABASE_URL: "postgresql://postgres@127.0.0.1:5432/postgres" },
      open.connect,
    );

    return { done, sent };
  }

  it("runs each file as one script, in order", async () => {
    const { done, sent } = run(["a.sql", "b.sql"]);
    const result = await done;

    expect(sent).toEqual(["select 1; select 2;", "select 3;"]);
    expect(result.code).toBe(0);
  });

  it("wraps the files in one transaction when asked", async () => {
    const { done, sent } = run(["--single-transaction", "a.sql", "b.sql"]);
    await done;

    expect(sent).toEqual([
      "begin",
      "select 1; select 2;",
      "select 3;",
      "commit",
    ]);
  });

  it("rolls back and names the failing file", async () => {
    const { done, sent } = run(
      ["--single-transaction", "a.sql", "b.sql"],
      "select 3;",
    );

    const result = await done;

    expect(sent.at(-1)).toBe("rollback");
    expect(result).toMatchObject({ code: 1, data: { failed: "b.sql" } });
  });
});
