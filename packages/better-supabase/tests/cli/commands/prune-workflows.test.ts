import { describe, expect, it } from "vitest";

import type { ConsentRequest } from "../../../src/cli/core/agent.ts";
import type { PgQueryable } from "../../../src/cli/db.ts";

import {
  dbPruneWorkflowsCommand,
  parseAge,
  runPruneWorkflows,
} from "../../../src/cli/commands/prune-workflows.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";

const LOCAL = { DATABASE_URL: "postgresql://postgres@127.0.0.1:5432/postgres" };

const REMOTE = {
  DATABASE_URL: "postgresql://postgres:pw@db.example.com/postgres",
};

function fakeDb(
  options: { deletes?: readonly number[]; installed?: boolean } = {},
): {
  sent: { text: string; values: readonly unknown[] | undefined }[];
  client: PgQueryable;
} {
  const sent: { text: string; values: readonly unknown[] | undefined }[] = [];
  const deletes = [...(options.deletes ?? [])];

  return {
    sent,
    client: {
      // SAFETY: each branch returns the row shape its query selects.
      query: ((text: string, values?: readonly unknown[]) => {
        sent.push({ text, values });

        if (text.includes("pg_catalog.pg_proc")) {
          return Promise.resolve({
            rows:
              options.installed === false
                ? []
                : [{ schema: "better_supabase" }],
          });
        }

        if (text.includes("workflow_purge_runs(")) {
          return Promise.resolve({ rows: [{ deleted: deletes.shift() ?? 0 }] });
        }

        if (text.startsWith("select count(*)")) {
          return Promise.resolve({ rows: [{ count: "4" }] });
        }

        return Promise.resolve({ rows: [] });
      }) as unknown as PgQueryable["query"],
    },
  };
}

const args = (argv: string[]) =>
  parseCommandArgs(dbPruneWorkflowsCommand, argv);

const config = resolveConfig({}, "/tmp/prune");

describe("parseAge", () => {
  it("reads days and hours", () => {
    expect(parseAge("30d")).toBe("30 days");
    expect(parseAge("12h")).toBe("12 hours");
    expect(parseAge("7 days")).toBe("7 days");
    expect(() => parseAge("1 week")).toThrow("--older-than");
  });
});

describe("runPruneWorkflows", () => {
  it("deletes in batches until one comes back short", async () => {
    const db = fakeDb({ deletes: [2, 2, 1] });

    const result = await runPruneWorkflows(
      config,
      args(["--older-than", "7d", "--batch-size", "2"]),
      LOCAL,
      { open: fakeConnect(db.client).connect },
    );

    expect(result.code).toBe(0);
    expect(result.data).toMatchObject({ deleted: 5, olderThan: "7 days" });

    const purges = db.sent.filter((entry) =>
      entry.text.includes("workflow_purge_runs("),
    );

    expect(purges).toHaveLength(3);
    expect(purges[0]?.values).toEqual([
      "7 days",
      ["completed", "failed", "cancelled"],
      2,
    ]);
  });

  it("counts on a dry run and writes nothing", async () => {
    const db = fakeDb();

    const result = await runPruneWorkflows(
      config,
      args(["--status", "failed", "--dry-run"]),
      REMOTE,
      {
        open: fakeConnect(db.client).connect,
        requireConsent: () => {
          throw new Error("no consent needed");
        },
      },
    );

    expect(result.data).toMatchObject({ pending: 4, statuses: ["failed"] });
    expect(
      db.sent.some((entry) => entry.text.includes("workflow_purge_runs(")),
    ).toBe(false);
  });

  it("asks for consent on a remote database", async () => {
    const requests: ConsentRequest[] = [];
    await runPruneWorkflows(config, args([]), REMOTE, {
      open: fakeConnect(fakeDb().client).connect,
      requireConsent: (request) => {
        requests.push(request);
      },
    });

    expect(requests[0]?.effect).toBe("database-write");
  });

  it("refuses a status that has not ended and a missing block", async () => {
    await expect(
      runPruneWorkflows(config, args(["--status", "running"]), LOCAL, {
        open: fakeConnect(fakeDb().client).connect,
      }),
    ).rejects.toThrow("Only ended runs");
    await expect(
      runPruneWorkflows(config, args([]), LOCAL, {
        open: fakeConnect(fakeDb({ installed: false }).client).connect,
      }),
    ).rejects.toThrow("workflow-sdk block");
  });

  it("refuses a batch size out of range", async () => {
    await expect(
      runPruneWorkflows(config, args(["--batch-size", "0"]), LOCAL, {
        open: fakeConnect(fakeDb().client).connect,
      }),
    ).rejects.toThrow("--batch-size takes a whole number");
  });

  it("says so when nothing ended long enough ago", async () => {
    const result = await runPruneWorkflows(config, args([]), LOCAL, {
      open: fakeConnect(fakeDb().client).connect,
    });

    expect(result.output).toBe("No runs ended more than 30 days ago.");
  });

  it("reports a failed query as a failed result", async () => {
    const client: PgQueryable = {
      query: () => Promise.reject(new Error("connection reset")),
    };

    const result = await runPruneWorkflows(config, args([]), LOCAL, {
      open: fakeConnect(client).connect,
    });

    expect(result).toMatchObject({ code: 1, errorCode: "failed" });
    expect(result.error).toContain("connection reset");
  });
});
