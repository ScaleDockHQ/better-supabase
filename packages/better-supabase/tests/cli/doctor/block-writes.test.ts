import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";
import type {
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { BLOCK_WRITE_RULES } from "../../../src/cli/doctor/block-writes.ts";
import { runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { snapshotFixture } from "../fixtures/library.ts";

const base = await parseSnapshot(snapshotFixture);

/** The fixture with a table of the app's named `public.credentials`. */
function withAppCredentials(): Snapshot {
  const catalog = structuredClone(toCatalog(base));

  const customers = catalog.tables.find(
    (table) => table.schema === "public" && table.name === "customers",
  );

  // SAFETY: a structured clone of the catalog, which the test owns.
  const tables = catalog.tables as CatalogTable[];
  tables.push({ ...customers!, id: 999_999, name: "credentials" });

  // SAFETY: the catalog is plain data; fromCatalog reads it back.
  return fromCatalog(catalog);
}

const run = (sources: readonly TextFile[], snapshot: Snapshot = base) =>
  runRules(
    {
      config: resolveConfig({ blocks: ["credentials"] }, "/project"),
      snapshot,
      configToml: undefined,
      envFiles: [],
      gitignore: "",
      sources,
    } satisfies DoctorContext,
    BLOCK_WRITE_RULES,
  );

const WRITES: TextFile = {
  path: "src/app/settings/actions.ts",
  text: [
    'import { createClient } from "@/lib/supabase/server";',
    "",
    "export async function save(supabase) {",
    '  await supabase.schema("better_supabase").from("credentials").insert({});',
    "  await supabase",
    '    .from("credentials")',
    '    .update({ name: "x" })',
    '    .eq("id", 1);',
    '  await supabase.from("credentials").select("*");',
    '  await supabase.schema("public").from("credentials").delete();',
    "}",
  ].join("\n"),
};

describe("BS351", () => {
  it("reports writes to a block's table, with and without .schema()", async () => {
    const findings = await run([WRITES]);

    expect(findings).toEqual([
      expect.objectContaining({
        code: "BS351",
        severity: "warning",
        target: "src/app/settings/actions.ts:4",
        location: { file: "src/app/settings/actions.ts", line: 4 },
        message: expect.stringContaining(
          "calls .insert() on better_supabase.credentials, the secrets table of blocks.credentials",
        ),
      }),
      expect.objectContaining({
        target: "src/app/settings/actions.ts:6",
        message: expect.stringContaining("calls .update()"),
      }),
    ]);
  });

  it("leaves a table of the app's with the same name alone", async () => {
    const findings = await run([WRITES], withAppCredentials());

    expect(findings.map((finding) => finding.target)).toEqual([
      "src/app/settings/actions.ts:4",
    ]);
  });

  it("stays quiet without blocks", async () => {
    expect(
      await runRules(
        {
          config: resolveConfig({}, "/project"),
          snapshot: base,
          configToml: undefined,
          envFiles: [],
          gitignore: "",
          sources: [WRITES],
        },
        BLOCK_WRITE_RULES,
      ),
    ).toEqual([]);
  });
});
