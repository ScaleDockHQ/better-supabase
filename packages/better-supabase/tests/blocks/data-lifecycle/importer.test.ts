import { describe, expect, it } from "vitest";

import type { RestoreFile } from "../../../src/blocks/data-lifecycle/index.ts";

import { createDataImporter } from "../../../src/blocks/data-lifecycle/index.ts";

const TABLES = [
  {
    name: "public.lines",
    tenantColumn: "organization_id",
    columns: ["id", "organization_id", "order_id", "qty"],
    keyColumns: ["id"],
    references: ["public.orders"],
  },
  {
    name: "public.orders",
    tenantColumn: "organization_id",
    columns: ["id", "organization_id", "name"],
    keyColumns: ["id"],
    references: [],
  },
  {
    name: "public.notes",
    tenantColumn: "organization_id",
    columns: ["organization_id", "body"],
    keyColumns: [],
    references: [],
  },
];

const file = (name: string, rows: readonly unknown[]): RestoreFile => ({
  name,
  text: () =>
    Promise.resolve(rows.map((row) => `${JSON.stringify(row)}\n`).join("")),
});

/** A transport that keeps a record map, as `import_upsert_batch` does. */
function fakeTransport(options: { failBatch?: boolean } = {}) {
  const calls: [string, Record<string, unknown>][] = [];
  const hashes = new Map<string, string>();
  let dryRun = false;

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        const answer = (): unknown => {
          switch (fn) {
            case "data_restore_tables": {
              return TABLES;
            }

            case "start_import_run": {
              dryRun =
                (args["options"] as { dryRun?: boolean } | undefined)
                  ?.dryRun === true;

              return { id: "run-1" };
            }

            case "mark_import_running":
            case "cancel_import_run": {
              return true;
            }

            case "import_upsert_batch": {
              if (options.failBatch) {
                throw new Error("connection lost");
              }

              const counts = {
                inserted: 0,
                updated: 0,
                unchanged: 0,
                conflicted: 0,
              };

              const items = args["items"] as { key: string; data: unknown }[];

              for (const item of items) {
                const hash = JSON.stringify(item.data);

                if (hashes.get(item.key) === hash) {
                  counts.unchanged += 1;
                } else if (hashes.has(item.key)) {
                  counts.updated += 1;
                } else {
                  counts.inserted += 1;
                }

                if (!dryRun) {
                  hashes.set(item.key, hash);
                }
              }

              return { ...counts, errors: [], dryRun };
            }

            case "finish_import_run": {
              return {};
            }

            default: {
              throw new Error(`unexpected call ${fn}`);
            }
          }
        };

        try {
          return Promise.resolve(answer());
        } catch (error) {
          return Promise.reject(error);
        }
      },
    },
  };
}

describe("createDataImporter", () => {
  it("writes parents first and a second restore writes nothing", async () => {
    const fake = fakeTransport();
    const importer = createDataImporter({ transport: fake.transport });

    const files = [
      file("exp-1/public.lines.ndjson", [
        { id: "l1", organization_id: "old", order_id: "o1", qty: 2 },
      ]),
      file("exp-1/public.orders.ndjson", [
        { id: "o1", organization_id: "old", name: "A" },
        { id: "o2", organization_id: "old", name: "B" },
      ]),
      file("exp-1/public.notes.ndjson", [
        { organization_id: "old", body: "x" },
      ]),
    ];

    const first = await importer
      .restore({ organizationId: "new", files })
      .orThrow();

    expect(first.tables.map((table) => table.table)).toEqual([
      "public.orders",
      "public.lines",
      "public.notes",
    ]);
    expect(first.written).toBe(4);
    expect(first.tables.map((table) => table.inserted)).toEqual([2, 1, 1]);

    const firstBatch = fake.calls.find(([fn]) => fn === "import_upsert_batch");

    const keys = (firstBatch![1]["items"] as { key: string }[]).map(
      (item) => item.key,
    );

    expect(keys).toEqual(['public.orders:["o1"]', 'public.orders:["o2"]']);
    expect(firstBatch![1]["entity"]).toBe("data_lifecycle_row");

    const second = await importer
      .restore({ organizationId: "new", files })
      .orThrow();

    expect(second.written).toBe(0);
    expect(second.tables.map((table) => table.unchanged)).toEqual([2, 1, 1]);
  });

  it("reports unknown tables and columns in a dry run and refuses them otherwise", async () => {
    const fake = fakeTransport();
    const importer = createDataImporter({ transport: fake.transport });

    const files = [
      file("public.orders.ndjson", [
        { id: "o1", organization_id: "old", name: "A", secret: "s" },
      ]),
      file("public.ghosts.ndjson", [{ id: "g" }]),
    ];

    const dry = await importer
      .restore({ organizationId: "new", files, dryRun: true })
      .orThrow();

    expect(dry.dryRun).toBe(true);
    expect(dry.unknownTables).toEqual(["public.ghosts"]);
    expect(dry.tables).toMatchObject([
      {
        table: "public.orders",
        rows: 1,
        inserted: 1,
        unknownColumns: ["secret"],
      },
    ]);
    expect(
      fake.calls.find(([fn]) => fn === "start_import_run")![1]["options"],
    ).toMatchObject({ dryRun: true });

    const refused = await importer.restore({ organizationId: "new", files });

    expect(refused.ok).toBe(false);
    expect(refused.error).toMatchObject({
      kind: "validation",
      hint: "DATA_RESTORE_UNKNOWN",
    });
    expect(
      fake.calls.filter(([fn]) => fn === "import_upsert_batch"),
    ).toHaveLength(1);
  });

  it("rejects CSV with a typed error", async () => {
    const fake = fakeTransport();
    const importer = createDataImporter({ transport: fake.transport });

    const result = await importer.restore({
      organizationId: "new",
      files: [
        { name: "public.orders.csv", text: () => Promise.resolve("id\n1\n") },
      ],
    });

    expect(result.error).toMatchObject({
      kind: "unsupported",
      hint: "DATA_RESTORE_CSV",
    });
    expect(fake.calls).toEqual([]);
  });

  it("rejects a line that is not a JSON object", async () => {
    const importer = createDataImporter({
      transport: fakeTransport().transport,
    });

    const result = await importer.restore({
      organizationId: "new",
      files: [
        {
          name: "public.orders.ndjson",
          text: () => Promise.resolve("{}\nnope\n"),
        },
      ],
    });

    expect(result.error).toMatchObject({
      kind: "validation",
      hint: "DATA_RESTORE_FORMAT",
    });
  });

  it("cancels the run when a batch fails", async () => {
    const fake = fakeTransport({ failBatch: true });
    const importer = createDataImporter({ transport: fake.transport });

    const result = await importer.restore({
      organizationId: "new",
      files: [
        file("public.orders.ndjson", [
          { id: "o1", organization_id: "old", name: "A" },
        ]),
      ],
    });

    expect(result.ok).toBe(false);
    expect(fake.calls.map(([fn]) => fn)).toContain("cancel_import_run");
  });

  it("limits the restore to the tables asked for", async () => {
    const fake = fakeTransport();

    const importer = createDataImporter({
      transport: fake.transport,
      batchSize: 1,
    });

    const report = await importer
      .restore({
        organizationId: "new",
        tables: ["public.orders"],
        files: [
          file("public.orders.ndjson", [
            { id: "o1", organization_id: "old", name: "A" },
            { id: "o2", organization_id: "old", name: "B" },
          ]),
          file("public.notes.ndjson", [{ organization_id: "old", body: "x" }]),
        ],
      })
      .orThrow();

    expect(report.tables.map((table) => table.table)).toEqual([
      "public.orders",
    ]);
    expect(
      fake.calls.filter(([fn]) => fn === "import_upsert_batch"),
    ).toHaveLength(2);
  });
});
