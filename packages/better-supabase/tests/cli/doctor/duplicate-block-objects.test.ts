import { describe, expect, it, vi } from "vitest";

import type { BlockSqlFileState } from "../../../src/cli/doctor/module-files.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { duplicatedBlockObjects } from "../../../src/cli/doctor/owned-columns.ts";

vi.mock(import("../../../src/cli/doctor/module-files.ts"), () => ({
  moduleFiles: (): Promise<BlockSqlFileState[]> =>
    // SAFETY: the check reads only `file.kind` and `file.contents`.
    Promise.resolve([
      {
        file: {
          kind: "schema",
          contents: [
            "create unique index inv_key on public.invoices (organization_id, direction, number);",
            "create trigger notes_touch before update on public.notes for each row execute function better_supabase.set_updated_at();",
          ].join("\n"),
        },
      },
      { file: { kind: "data", contents: "select 1;" } },
    ] as unknown as BlockSqlFileState[]),
}));

const context = (): DoctorContext =>
  // SAFETY: the check reads only config.schemas and sqlFiles.
  ({
    config: { schemas: ["public"] },
    sqlFiles: [
      {
        path: "supabase/schemas/app.sql",
        text: "create unique index own_number on public.invoices (organization_id, number);\nselect better_supabase.track_updated_at('public.notes');",
      },
      {
        path: "supabase/migrations/20260101000000_old.sql",
        text: "create unique index old on public.invoices (direction);",
      },
    ],
  }) as unknown as DoctorContext;

describe("duplicatedBlockObjects", () => {
  it("reports a block index your unique index makes redundant", async () => {
    expect(await duplicatedBlockObjects(context(), "index")).toEqual([
      expect.objectContaining({
        target: "public.invoices.inv_key",
        message: expect.stringContaining(
          "is weaker than your index own_number",
        ),
      }),
    ]);
  });

  it("reports a block updated_at trigger next to track_updated_at", async () => {
    expect(await duplicatedBlockObjects(context(), "trigger")).toEqual([
      expect.objectContaining({
        target: "public.notes.notes_touch",
        message: expect.stringContaining("track_updated_at('public.notes')"),
      }),
    ]);
  });
});
