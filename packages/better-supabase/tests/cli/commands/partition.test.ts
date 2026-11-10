import { describe, expect, it } from "vitest";

import type { PgQueryable } from "../../../src/cli/db.ts";

import {
  dbPartitionCommand,
  runPartition,
} from "../../../src/cli/commands/partition.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

const LOCAL = { DATABASE_URL: "postgresql://postgres@127.0.0.1:5432/postgres" };

const config = resolveConfig({}, "/tmp/partition");

const args = (argv: string[]) => parseCommandArgs(dbPartitionCommand, argv);

function fakeDb(schema: string | null): {
  readonly sent: string[];
  readonly client: PgQueryable;
} {
  const sent: string[] = [];

  return {
    sent,
    client: {
      // SAFETY: the procedure lookup returns the schema row, the call returns nothing.
      query: ((text: string) => {
        sent.push(text);

        return Promise.resolve({
          rows: text.includes("pg_proc") && schema ? [{ schema }] : [],
        });
      }) as unknown as PgQueryable["query"],
    },
  };
}

describe("db partition audit", () => {
  it("calls the procedure it finds, with the batch size", async () => {
    const db = fakeDb("better_supabase");
    const { connect } = fakeConnect(db.client);

    const result = await runPartition(
      config,
      args(["audit", "--batch-size", "1000", "--drop-old"]),
      LOCAL,
      { open: connect },
    );

    expect(result.code).toBe(0);
    expect(db.sent.at(-1)).toBe(
      'call "better_supabase"."convert_audit_log_to_partitioned"(1000, true)',
    );
  });

  it("changes nothing with --dry-run", async () => {
    const db = fakeDb("better_supabase");
    const { connect } = fakeConnect(db.client);

    const result = await runPartition(
      config,
      args(["audit", "--dry-run"]),
      LOCAL,
      { open: connect },
    );

    expect(result.code).toBe(0);
    expect(db.sent.some((text) => text.startsWith("call"))).toBe(false);
  });

  it("says what to do when the procedure is missing", async () => {
    const { connect } = fakeConnect(fakeDb(null).client);

    await expect(
      runPartition(config, args(["audit"]), LOCAL, { open: connect }),
    ).rejects.toThrow(/options\.partitioned/u);
  });

  it("rejects another target and a bad batch size", async () => {
    const { connect } = fakeConnect(fakeDb("better_supabase").client);

    await expect(
      runPartition(config, args(["tasks"]), LOCAL, { open: connect }),
    ).rejects.toThrow(/audit/u);
    await expect(
      runPartition(config, args(["audit", "--batch-size", "0"]), LOCAL, {
        open: connect,
      }),
    ).rejects.toThrow(/positive integer/u);
  });
});
