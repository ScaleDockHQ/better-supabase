import { describe, expect, it } from "vitest";

import {
  importChunkHandler,
  importChunkSchema,
  runImportWorker,
} from "../../../src/blocks/imports/chunks.ts";
import { createImports } from "../../../src/blocks/imports/imports.ts";

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

describe("import chunks", () => {
  it("stores a chunk's items in the batch shape", async () => {
    const t = transport({ store_import_chunk: true });
    const imports = createImports({ transport: t });

    const stored = await imports.chunks
      .store({
        runId: "run-1",
        entity: "customer",
        chunk: 2,
        items: [{ key: "c1", data: { name: "Alpha" } }],
      })
      .orThrow();

    expect(stored).toBe(true);
    expect(t.calls[0]).toEqual({
      fn: "store_import_chunk",
      args: {
        run: "run-1",
        entity: "customer",
        chunk: 2,
        items: [{ key: "c1", scope: "", data: { name: "Alpha" }, refs: {} }],
      },
    });
  });

  it("decodes a processed, a done and a skipped chunk", async () => {
    const processed = createImports({
      transport: transport({
        process_import_chunk: {
          inserted: 3,
          updated: 1,
          unchanged: 0,
          conflicted: 0,
          errors: [{ key: "c9", code: "IMPORT_ITEM_INVALID", message: "bad" }],
        },
      }),
    });

    expect(
      await processed.chunks
        .process({ runId: "r", entity: "customer", chunk: 0 })
        .orThrow(),
    ).toEqual({
      status: "processed",
      inserted: 3,
      updated: 1,
      unchanged: 0,
      conflicted: 0,
      errors: [{ key: "c9", code: "IMPORT_ITEM_INVALID", message: "bad" }],
    });

    const done = createImports({
      transport: transport({
        process_import_chunk: { inserted: 3, done: true },
      }),
    });

    expect(
      (
        await done.chunks
          .process({ runId: "r", entity: "customer", chunk: 0 })
          .orThrow()
      ).status,
    ).toBe("done");

    const skipped = createImports({
      transport: transport({ process_import_chunk: { skipped: true } }),
    });

    expect(
      await skipped.chunks
        .process({ runId: "r", entity: "customer", chunk: 0 })
        .orThrow(),
    ).toEqual({ status: "skipped" });
  });

  it("reads the progress counts", async () => {
    const imports = createImports({
      transport: transport({
        import_chunk_progress: { pending: 2, claimed: 1, done: 5, failed: 1 },
      }),
    });

    expect(await imports.chunks.progress("r").orThrow()).toEqual({
      pending: 2,
      claimed: 1,
      done: 5,
      failed: 1,
    });
  });

  it("marks a chunk failed and reads a failed chunk back", async () => {
    const imports = createImports({
      transport: transport({
        fail_import_chunk: true,
        process_import_chunk: { failed: true, message: "bad file" },
      }),
    });

    expect(
      await imports.chunks
        .fail({ runId: "r", entity: "customer", chunk: 1, message: "bad file" })
        .orThrow(),
    ).toBe(true);
    expect(
      await imports.chunks
        .process({ runId: "r", entity: "customer", chunk: 1 })
        .orThrow(),
    ).toEqual({ status: "failed", message: "bad file" });
  });

  it("validates the job payload", () => {
    const validate = importChunkSchema["~standard"].validate;

    expect(validate({ run: "r", entity: "customer", chunk: 3 })).toEqual({
      value: { run: "r", entity: "customer", chunk: 3 },
    });
    expect(
      validate({ run: "r", entity: "customer", chunk: -1 }),
    ).toHaveProperty("issues");
    expect(validate("nope")).toHaveProperty("issues");
  });

  it("processes the chunk a job names and fails the job when the call fails", async () => {
    const t = transport({ process_import_chunk: { inserted: 1 } });
    const handler = importChunkHandler(createImports({ transport: t }));

    await expect(
      handler({ run: "run-1", entity: "customer", chunk: 4 }),
    ).resolves.toMatchObject({ status: "processed", inserted: 1 });
    expect(t.calls[0]?.args).toEqual({
      run: "run-1",
      entity: "customer",
      chunk: 4,
    });

    const failing = importChunkHandler(
      createImports({
        transport: { call: () => Promise.reject(new Error("connection lost")) },
      }),
    );

    await expect(
      failing({ run: "run-1", entity: "customer", chunk: 4 }),
    ).rejects.toThrow(/connection lost|DbException|Error/);
  });

  it("runs the worker on the imports queue with its options", async () => {
    const seen: Record<string, unknown>[] = [];
    const abort = new AbortController();

    const result = await runImportWorker({
      imports: createImports({
        transport: transport({ process_import_chunk: { inserted: 1 } }),
      }),
      queue: {
        work: async (input) => {
          seen.push(input);

          await input.handler({ run: "r", entity: "customer", chunk: 0 });

          return { succeeded: 1, failed: 0 };
        },
      },
      concurrency: 4,
      signal: abort.signal,
    });

    expect(result).toEqual({ succeeded: 1, failed: 0 });
    expect(seen[0]).toMatchObject({
      queue: "imports",
      concurrency: 4,
      signal: abort.signal,
    });
  });
});
