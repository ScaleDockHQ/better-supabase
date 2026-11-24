import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type MutableCatalog = { -readonly [K in keyof Catalog]: Catalog[K] };

type MutableTable = { -readonly [K in keyof CatalogTable]: CatalogTable[K] };

function snapshot(change: (notes: MutableTable) => void): Snapshot {
  const copy = structuredClone(toCatalog(base)) as MutableCatalog;

  const notes = (copy.tables as MutableTable[]).find(
    (entry) => entry.name === "notes",
  )!;

  change(notes);

  return fromCatalog(copy);
}

const SOURCE = `
export const plans = bsb.kept(async (ctx) => ctx.db.notes.list(), {
  name: "plans",
  tables: ["notes"],
  share: "public",
});
export const mine = bsb.kept(async (ctx) => ctx.db.notes.list(), {
  name: "mine",
  tables: ["notes"],
});
`;

const context = (snap: Snapshot): DoctorContext => ({
  config: resolveConfig({}, "/project"),
  snapshot: snap,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [
    { path: "src/lib/plans.ts", text: SOURCE },
    { path: "src/lib/other.ts", text: "export const other = 1;\n" },
  ],
});

const run = (snap: Snapshot) =>
  runRules(
    context(snap),
    RULES.filter((rule) => rule.code === "BS645"),
  );

describe("BS645", () => {
  it("reports a public kept entry on a table with no anon select policy", async () => {
    const findings = await run(
      snapshot((notes) => {
        notes.rls = true;
        notes.grants = [{ role: "anon", privileges: ["SELECT"] }];
        notes.policies = [];
      }),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain('bsb.kept("plans")');
    expect(findings[0]?.message).toContain("no select policy applies to anon");
    expect(findings[0]?.location).toMatchObject({ file: "src/lib/plans.ts" });
  });

  it("reports a table anon has no select grant on", async () => {
    const findings = await run(
      snapshot((notes) => {
        notes.grants = [{ role: "authenticated", privileges: ["SELECT"] }];
      }),
    );

    expect(findings[0]?.message).toContain("no select grant");
  });

  it("passes a table with an anon grant and select policy", async () => {
    const findings = await run(
      snapshot((notes) => {
        notes.rls = true;
        notes.grants = [{ role: "anon", privileges: ["SELECT"] }];
        notes.policies = [
          {
            name: "public_reads",
            command: "select",
            roles: ["anon"],
            permissive: true,
            using: "published",
            check: null,
          },
        ];
      }),
    );

    expect(findings).toEqual([]);
  });
});
