import { describe, expect, it } from "vitest";

import {
  defineImport,
  runImport,
} from "../../../src/blocks/imports/define-import.ts";
import { createImports } from "../../../src/blocks/imports/imports.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

function transport(results: Record<string, unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });

      return Promise.resolve(results[fn]);
    },
  };
}

const ORG = "org-1";

const runRow = {
  id: "run-1",
  organizationId: ORG,
  source: "erp",
  status: "running",
  mapping: {},
  counts: {
    customer: { inserted: 2, updated: 1, unchanged: 3, conflicted: 0 },
  },
  errors: [
    {
      entity: "customer",
      key: "c9",
      code: "IMPORT_ITEM_INVALID",
      message: "bad",
    },
  ],
  dryRun: false,
  full: true,
  inputChecksum: null,
  correlationId: "job-7",
  scopeAliases: [{ scope: "B", of: "A", entities: ["customer"] }],
  createdBy: null,
  createdAt: "2026-10-30T10:00:00Z",
  startedAt: "2026-10-30T10:00:05Z",
  finishedAt: null,
};

describe("imports client", () => {
  it("starts a run with its options", async () => {
    const t = transport({ start_import_run: { id: "run-1" } });
    const imports = createImports({ transport: t });

    const result = await imports.runs
      .start(ORG, "erp", {
        full: true,
        dryRun: false,
        correlationId: "job-7",
        scopeAliases: [{ scope: "B", of: "A", entities: ["customer"] }],
      })
      .orThrow();

    expect(result).toEqual({ id: "run-1" });
    expect(t.calls[0]).toEqual({
      fn: "start_import_run",
      args: {
        tenant: ORG,
        source: "erp",
        options: {
          dryRun: false,
          full: true,
          correlationId: "job-7",
          scopeAliases: [{ scope: "B", of: "A", entities: ["customer"] }],
        },
      },
    });
  });

  it("reads a run with counts per entity and decoded times", async () => {
    const imports = createImports({
      transport: transport({ get_import_run: runRow }),
    });

    const run = await imports.runs.get("run-1").orThrow();

    expect(run.source).toBe("erp");
    expect(run.status).toBe("running");
    expect(run.counts["customer"]).toEqual({
      inserted: 2,
      updated: 1,
      unchanged: 3,
      conflicted: 0,
      missing: 0,
    });
    expect(run.errors[0]).toMatchObject({ code: "IMPORT_ITEM_INVALID" });
    expect(run.scopeAliases).toEqual([
      { scope: "B", of: "A", entities: ["customer"] },
    ]);
    expect(run.startedAt?.toString()).toBe("2026-10-30T10:00:05Z");
    expect(run.finishedAt).toBeNull();
  });

  it("lists runs by source and status", async () => {
    const t = transport({ list_import_runs: [runRow] });
    const imports = createImports({ transport: t });

    const runs = await imports.runs
      .list(ORG, { source: "erp", status: "running", limit: 5 })
      .orThrow();

    expect(runs).toHaveLength(1);
    expect(t.calls[0]?.args).toEqual({
      tenant: ORG,
      source: "erp",
      status: "running",
      row_limit: 5,
    });
  });

  it("cancels a run", async () => {
    const imports = createImports({
      transport: transport({ cancel_import_run: true }),
    });

    expect(await imports.runs.cancel("run-1").orThrow()).toBe(true);
  });

  it("sends a batch of items and decodes the outcome", async () => {
    const t = transport({
      import_upsert_batch: {
        inserted: 1,
        updated: 0,
        unchanged: 1,
        conflicted: 1,
        errors: [{ key: "c4", code: "IMPORT_ITEM_INVALID", message: "bad" }],
        dryRun: false,
      },
    });

    const imports = createImports({ transport: t });

    const result = await imports
      .upsertBatch("run-1", "customer", [
        { key: "c1", data: { name: "Alpha" } },
        {
          key: "c2",
          scope: "A",
          data: { name: "Beta" },
          refs: { owner: "u1" },
        },
      ])
      .orThrow();

    expect(result).toEqual({
      inserted: 1,
      updated: 0,
      unchanged: 1,
      conflicted: 1,
      errors: [{ key: "c4", code: "IMPORT_ITEM_INVALID", message: "bad" }],
      dryRun: false,
    });
    expect(t.calls[0]?.args["items"]).toEqual([
      { key: "c1", scope: "", data: { name: "Alpha" }, refs: {} },
      { key: "c2", scope: "A", data: { name: "Beta" }, refs: { owner: "u1" } },
    ]);
  });

  it("resolves keys to the subjects they imported", async () => {
    const t = transport({
      import_resolve: [
        {
          key: "c1",
          scope: "",
          role: "primary",
          subjectType: "customer",
          subjectId: "s-1",
        },
      ],
    });

    const imports = createImports({ transport: t });

    const found = await imports
      .resolve("run-1", "customer", ["c1", { key: "c2", scope: "A" }])
      .orThrow();

    expect(found).toEqual([
      {
        key: "c1",
        scope: "",
        role: "primary",
        subjectType: "customer",
        subjectId: "s-1",
      },
    ]);
    expect(t.calls[0]?.args["keys"]).toEqual([
      { key: "c1" },
      { key: "c2", scope: "A" },
    ]);
  });

  it("finishes a run with its counts", async () => {
    const imports = createImports({
      transport: transport({
        finish_import_run: {
          customer: {
            inserted: 1,
            updated: 0,
            unchanged: 0,
            conflicted: 0,
            missing: 4,
          },
        },
      }),
    });

    const counts = await imports.finish("run-1").orThrow();

    expect(counts["customer"]?.missing).toBe(4);
  });

  it("keeps the legacy start", async () => {
    const t = transport({ start_import: { id: "run-9" } });
    const imports = createImports({ transport: t });

    expect(await imports.start(ORG, "people").orThrow()).toEqual({
      id: "run-9",
    });
    expect(t.calls[0]?.args).toEqual({
      tenant: ORG,
      source: "people",
      mapping: {},
    });
  });
});

describe("runImport through a target", () => {
  const columns = {
    "~standard": {
      version: 1 as const,
      vendor: "test",
      validate: (value: unknown) => ({
        value: value as { id: string; name: string },
      }),
    },
  };

  it("sends the rows to upsertBatch and totals the counts", async () => {
    const sent: { entity: string; keys: string[] }[] = [];

    const definition = defineImport({
      source: "erp",
      columns,
      key: (row) => row.id,
      target: {
        entity: "customer",
        item: (row) => ({ data: { name: row.name }, scope: "A" }),
      },
    });

    const result = await runImport(
      definition,
      "id,name\nc1,Alpha\nc2,Beta\n",
      { id: "id", name: "name" },
      {
        organizationId: ORG,
        start: async () => "run-1",
        finish: async () => {},
        upsertBatch: async (entity, items) => {
          sent.push({ entity, keys: items.map((item) => item.key) });

          return {
            inserted: 1,
            updated: 0,
            unchanged: 1,
            conflicted: 0,
            errors: [],
          };
        },
      },
    );

    expect(sent).toEqual([{ entity: "customer", keys: ["c1", "c2"] }]);
    expect(result).toMatchObject({
      status: "completed",
      counts: { inserted: 1, updated: 0, unchanged: 1, conflicted: 0 },
    });
  });

  it("fails the run when the target reports an item error", async () => {
    const finished: string[] = [];

    const definition = defineImport({
      source: "erp",
      columns,
      key: (row) => row.id,
      target: {
        entity: "customer",
        item: (row) => ({ data: { name: row.name } }),
      },
    });

    const result = await runImport(
      definition,
      "id,name\nc1,Alpha\n",
      { id: "id", name: "name" },
      {
        organizationId: ORG,
        start: async () => "run-2",
        finish: async (_id, status) => {
          finished.push(status);
        },
        upsertBatch: async () => ({
          inserted: 0,
          updated: 0,
          unchanged: 0,
          conflicted: 0,
          errors: [{ key: "c1", code: "IMPORT_ITEM_INVALID", message: "bad" }],
        }),
      },
    );

    expect(result.status).toBe("failed");
    expect(finished).toEqual(["failed"]);
  });

  it("needs an insert or a target", () => {
    expect(() =>
      defineImport({ source: "erp", columns, key: (row) => row.id }),
    ).toThrow(/insert function or a target/);
  });
});

describe("imports SQL", () => {
  it("renders the record map, the upsert and the targets from the options", () => {
    const sql = renderBlocks(["imports"], {
      modules: {
        imports: {
          options: {
            targets: {
              customer: {
                subjectType: "customer",
                write: "public.import_customer",
                updatedAt: "public.import_customer_updated_at",
              },
            },
          },
        },
      },
    })
      .filter((file) => file.module === "imports")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("import_records");
    expect(sql).toContain("import_upsert_batch");
    expect(sql).toContain('"public"."import_customer"(');
    expect(sql).toContain('"public"."import_customer_updated_at"(');
    expect(sql).toContain("IMPORT_RUN_ACTIVE");
  });

  it("refuses a target that is not a qualified function", () => {
    expect(() =>
      renderBlocks(["imports"], {
        modules: {
          imports: {
            options: {
              targets: {
                customer: { subjectType: "customer", write: "drop table x" },
              },
            },
          },
        },
      }),
    ).toThrow(/write/);
  });
});
