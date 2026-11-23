import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogPolicy,
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

function snapshot(
  change: (tables: CatalogTable[], catalog: MutableCatalog) => void,
): Snapshot {
  const copy = structuredClone(toCatalog(base)) as MutableCatalog;

  change(copy.tables as CatalogTable[], copy);

  return fromCatalog(copy);
}

const table = (tables: CatalogTable[], name: string) =>
  tables.find((entry) => entry.name === name)! as {
    -readonly [K in keyof CatalogTable]: CatalogTable[K];
  };

const context = (snap: Snapshot, doctor: object = {}): DoctorContext => ({
  config: resolveConfig(
    {
      auth: { tenant: { column: "organization_id" } },
      doctor,
      authorization: {
        apiVersion: 1,
        name: "acme",
        functions: { can: "acme.authz_can({permission})" },
      },
    } as Parameters<typeof resolveConfig>[0],
    "/project",
  ),
  snapshot: snap,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
});

const run = (ctx: DoctorContext, code: string) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

const policy = (overrides: Partial<CatalogPolicy>): CatalogPolicy => ({
  name: "notes_extra",
  command: "select",
  roles: ["authenticated"],
  permissive: true,
  using: "true",
  check: null,
  functions: [],
  ...overrides,
});

const crowded = snapshot((tables) => {
  table(tables, "notes").policies = [
    policy({ name: "bsb_session_active", permissive: false, command: "all" }),
    policy({ name: "acme_can_read", functions: ["acme.authz_can"] }),
    policy({ name: "owner_reads" }),
    policy({ name: "team_reads" }),
    policy({ name: "public_reads", roles: [] }),
    policy({ name: "owner_inserts", command: "insert" }),
  ];
});

describe("many policies for one command (BS641)", () => {
  it("lists each policy of a crowded command with its kind and origin", async () => {
    const findings = await run(context(crowded), "BS641");

    expect(findings).toHaveLength(1);
    expect(findings[0]).toMatchObject({ target: "public.notes.select" });
    expect(findings[0]?.message).toContain(
      "bsb_session_active (restrictive, library)",
    );
    expect(findings[0]?.message).toContain(
      "acme_can_read (permissive, provider)",
    );
    expect(findings[0]?.message).toContain("owner_reads (permissive, app)");
  });

  it("follows doctor.policies.max", async () => {
    expect(
      await run(context(crowded, { policies: { max: 5 } }), "BS641"),
    ).toEqual([]);
  });
});

describe("indexes that lead with an enum column under RLS (BS642)", () => {
  it("reports an index whose first column is an enum", async () => {
    const enumLed = snapshot((tables, catalog) => {
      const notes = table(tables, "notes");
      const first = notes.columns[1]!;

      catalog.enums = [
        ...catalog.enums,
        { schema: "public", name: "note_kind", values: ["a", "b"] },
      ];
      notes.columns = notes.columns.map((column) =>
        column.name === first.name
          ? { ...column, isEnum: true, udt: "note_kind", typeSchema: "public" }
          : column,
      );
      notes.indexes = [
        ...notes.indexes,
        {
          name: "notes_kind_idx",
          columns: [first.name],
          unique: false,
          primary: false,
          partial: false,
        },
      ];
    });

    const findings = await run(context(enumLed), "BS642");

    expect(findings.map((finding) => finding.target)).toContain(
      "public.notes.notes_kind_idx",
    );
    expect(await run(context(crowded), "BS642")).toEqual([]);
  });
});

describe("functions by caller (BS643)", () => {
  it("counts each schema's functions by caller class", async () => {
    const withInventory: Snapshot = {
      ...crowded,
      extras: {
        ...crowded.extras,
        functionInventory: [
          {
            schema: "public",
            name: "my_rpc",
            signature: "",
            execute: ["authenticated"],
            policy: false,
            trigger: false,
          },
          {
            schema: "public",
            name: "audit_row",
            signature: "",
            execute: [],
            policy: false,
            trigger: true,
          },
        ],
      },
    };

    expect(await run(context(withInventory), "BS643")).toMatchObject([
      {
        target: "public",
        message: expect.stringContaining(
          "public: 0 policy, 1 trigger, 1 app RPC, 0 service only, 0 unreferenced",
        ),
      },
    ]);
    expect(await run(context(crowded), "BS643")).toEqual([]);
  });
});
