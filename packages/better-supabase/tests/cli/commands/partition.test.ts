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

  it("asks for consent on a remote database and reports the default batch", async () => {
    const db = fakeDb("better_supabase");
    const { connect } = fakeConnect(db.client);
    const asked: string[] = [];

    const result = await runPartition(
      config,
      args(["audit"]),
      { DATABASE_URL: "postgresql://postgres@db.example.com:5432/postgres" },
      {
        open: connect,
        requireConsent: (request) => {
          asked.push(request.detail);
        },
      },
    );

    expect(asked).toHaveLength(1);
    expect(asked[0]).toContain("db.example.com");
    expect(db.sent.at(-1)).toContain("(50000, false)");
    expect(result.output).toContain("--drop-old");
  });

  it("reports a failing call as a failed command", async () => {
    const failing: PgQueryable = {
      // SAFETY: the lookup answers a schema, the call rejects.
      query: ((text: string) =>
        text.startsWith("call")
          ? Promise.reject(new Error("lock timeout"))
          : Promise.resolve({
              rows: [{ schema: "better_supabase" }],
            })) as unknown as PgQueryable["query"],
    };

    const { connect } = fakeConnect(failing);

    const result = await runPartition(config, args(["audit"]), LOCAL, {
      open: connect,
    });

    expect(result).toMatchObject({ code: 1, errorCode: "failed" });
    expect(result.error).toContain("lock timeout");
  });

  it("says the table is dropped with --drop-old", async () => {
    const { connect } = fakeConnect(fakeDb("better_supabase").client);

    const result = await runPartition(
      config,
      args(["audit", "--drop-old"]),
      LOCAL,
      { open: connect },
    );

    expect(result.output).toContain("dropped");
  });

  it("runs without injected dependencies", async () => {
    const { connect } = fakeConnect(fakeDb("better_supabase").client);

    const result = await runPartition(
      config,
      args(["audit"]),
      { DATABASE_URL: "postgresql://postgres@db.example.com:5432/postgres" },
      { open: connect },
    );

    expect(result.code).toBe(0);
  });
});
