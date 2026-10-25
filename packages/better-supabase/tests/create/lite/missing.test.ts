import { expect, test, vi } from "vitest";

import type { LiteRuntime } from "../../../src/lite/runtime.ts";

vi.mock(import("../../../src/lite/runtime.ts"), async (importOriginal) => ({
  ...(await importOriginal()),
  loadLite: () => Promise.resolve(undefined),
}));

test("validateDesign says how to install Lite when it is missing", async () => {
  const { validateDesign } = await import("../../../src/create/lite/index.ts");

  await expect(validateDesign([])).rejects.toThrow(/@supabase\/lite/u);
});

test("a thrown non-Error becomes the issue message", async () => {
  const { validateDesign } = await import("../../../src/create/lite/index.ts");

  const result = await validateDesign(
    [{ path: "a.sql", module: "a", contents: "select 1" }],
    {
      runtime: {
        App: vi.fn<LiteRuntime["App"]>(),
        createSqliteConnection: () => Promise.reject(new Error("unused")),
        createPgliteConnection: () =>
          Promise.resolve({
            createMigrator: () => ({ migrate: () => Promise.resolve() }),
            translateDdl: () => Promise.resolve(),
            transaction: () => Promise.resolve(),
            close: () => Promise.resolve(),
            driver: {
              exec: (sql: string) =>
                sql.includes("create schema")
                  ? Promise.resolve()
                  : Promise.reject("boom"),
              query: () => Promise.resolve({ rows: [] }),
            },
          }),
      },
    },
  );

  expect(result.tables).toBe(0);
  expect(result.issues).toEqual([
    {
      code: "sql_error",
      severity: "error",
      source: "sql",
      path: "",
      table: "a",
      file: "a.sql",
      message: "boom",
    },
  ]);
});
