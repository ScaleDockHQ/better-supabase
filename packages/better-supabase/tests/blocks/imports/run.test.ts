import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import { runImport } from "../../../src/blocks/imports/define-import.ts";

interface Row {
  readonly email: string;
}

const columns: StandardSchemaV1<unknown, Row> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => {
      const record = typeof value === "object" && value !== null ? value : {};
      const email = "email" in record ? record.email : undefined;

      if (typeof email !== "string" || email.length === 0) {
        return { issues: [{ message: "email required" }] };
      }

      return { value: { email } };
    },
  },
};

describe("runImport", () => {
  it("skips keys that already imported and finishes completed", async () => {
    const inserted: Row[][] = [];
    const finished: string[] = [];

    const result = await runImport(
      {
        kind: "people",
        columns,
        key: (row) => row.email,
        insert: async (batch) => {
          inserted.push([...batch]);
        },
      },
      "email\na@x.test\na@x.test\nb@x.test\n",
      { email: "email" },
      {
        organizationId: "org-1",
        importedKeys: new Set(["b@x.test"]),
        start: async () => "run-1",
        finish: async (id, status, count) => {
          finished.push(`${id}:${status}:${count}`);
        },
      },
    );

    expect(result).toMatchObject({
      id: "run-1",
      status: "completed",
      imported: 1,
    });
    expect(inserted).toEqual([[{ email: "a@x.test" }]]);
    expect(finished).toEqual(["run-1:completed:1"]);
  });

  it("finishes failed and inserts nothing when a row is invalid", async () => {
    const inserted: number[] = [];

    const result = await runImport(
      {
        kind: "people",
        columns,
        key: (row) => row.email,
        insert: async (batch) => {
          inserted.push(batch.length);
        },
      },
      "email\n\n",
      { email: "email" },
      {
        organizationId: "org-1",
        start: async () => "run-2",
        finish: async (_id, status, count, error) => {
          expect(status).toBe("failed");
          expect(count).toBe(0);
          expect(error).toContain("Invalid people row 2");
        },
      },
    );

    expect(result.status).toBe("failed");
    expect(inserted).toEqual([]);
  });

  it("marks the run running and finishes failed when a batch throws", async () => {
    const calls: string[] = [];
    const csv = `email\n${Array.from({ length: 150 }, (_, i) => `p${i}@x.test`).join("\n")}\n`;
    let batches = 0;

    const result = await runImport(
      {
        kind: "people",
        columns,
        key: (row) => row.email,
        insert: async () => {
          batches += 1;

          if (batches === 2) {
            throw new Error("duplicate key");
          }
        },
      },
      csv,
      { email: "email" },
      {
        organizationId: "org-1",
        start: async () => "run-3",
        running: async (id) => {
          calls.push(`${id}:running`);
        },
        finish: async (id, status, count, error) => {
          calls.push(`${id}:${status}:${count}:${error}`);
        },
      },
    );

    expect(calls).toEqual(["run-3:running", "run-3:failed:100:duplicate key"]);
    expect(result).toMatchObject({ status: "failed", imported: 100 });
    expect(result.rows).toHaveLength(100);
    expect(result.errors[0]?.message).toContain("imported row 101");
  });
});
