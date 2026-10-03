import { describe, expect, it } from "vitest";

import type {
  Catalog,
  CatalogPolicy,
  CatalogTable,
  ExtrasFunction,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { kitSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = parseSnapshot(fixture);

function snapshot(change: (tables: CatalogTable[]) => void): Snapshot {
  const copy = structuredClone(toCatalog(base)) as {
    -readonly [K in keyof Catalog]: Catalog[K];
  };
  change(copy.tables as CatalogTable[]);
  return fromCatalog(copy);
}

const table = (tables: CatalogTable[], name: string) =>
  tables.find((entry) => entry.name === name)! as {
    -readonly [K in keyof CatalogTable]: CatalogTable[K];
  };

const context = (
  snap: Snapshot,
  extra: Partial<DoctorContext> = {},
): DoctorContext => ({
  config: resolveConfig({ plugins: { tenant: true } }, "/project"),
  snapshot: snap,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  ...extra,
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

describe("policy security rules", () => {
  it("pass the fixture schema", async () => {
    for (const code of [
      "BS109",
      "BS110",
      "BS111",
      "BS112",
      "BS113",
      "BS114",
      "BS215",
    ])
      expect(await run(context(base), code)).toEqual([]);
  });

  it("flags auth.role() in policies and functions (BS109)", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy({ using: "(auth.role() = 'authenticated'::text)" }),
      ];
    });
    snap.generator.functions.push({
      ...snap.generator.functions[0]!,
      schema: "public",
      name: "is_staff",
      definition: "select auth.role() = 'service_role'",
    });
    const findings = await run(context(snap), "BS109");
    expect(findings.map((finding) => finding.target)).toEqual([
      "public.notes.notes_extra",
      "public.is_staff",
    ]);
    expect(findings[0]!.message).toContain("to authenticated");
  });

  it("flags update policies without a select policy or with check (BS110)", async () => {
    const blind = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy({ command: "update", check: "true" }),
      ];
    });
    expect(await run(context(blind), "BS110")).toMatchObject([
      {
        severity: "warning",
        message: expect.stringContaining("no select policy does"),
      },
    ]);
    const unchecked = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy({ name: "notes_read" }),
        policy({ command: "update" }),
      ];
    });
    expect(await run(context(unchecked), "BS110")).toMatchObject([
      { severity: "info", message: expect.stringContaining("with check") },
    ]);
  });

  it("flags needless and unused API grants (BS111)", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").grants = [
        { role: "authenticated", privileges: ["SELECT", "TRUNCATE"] },
        { role: "anon", privileges: ["SELECT"] },
      ];
    });
    expect(await run(context(snap), "BS111")).toMatchObject([
      {
        severity: "info",
        target: "public.notes:anon:unused",
        message: expect.stringContaining(
          "revoke select on table public.notes from anon;",
        ),
      },
      {
        severity: "warning",
        message: expect.stringContaining(
          "revoke truncate on table public.notes from authenticated;",
        ),
      },
    ]);
  });

  it("flags exposed security definer functions without a caller check (BS112)", async () => {
    const definer: ExtrasFunction = {
      schema: "public",
      name: "wipe",
      signature: "org uuid",
      language: "sql",
      volatility: "volatile",
      securityDefiner: true,
      settings: { search_path: '""' },
      execute: ["anon", "authenticated"],
    };
    const withFunction = (body: string, fn = definer): Snapshot => ({
      ...base,
      generator: {
        ...base.generator,
        functions: [
          ...base.generator.functions,
          {
            ...base.generator.functions[0]!,
            schema: fn.schema,
            name: fn.name,
            definition: body,
          },
        ],
      },
      extras: { ...base.extras, functions: [fn] },
    });
    const open = "delete from public.notes where organization_id = org";
    expect(await run(context(withFunction(open)), "BS112")).toMatchObject([
      {
        target: "public.wipe",
        message: expect.stringContaining(
          "revoke execute on function public.wipe(org uuid) from anon, authenticated;",
        ),
      },
    ]);
    const checked = `${open} and (select auth.uid()) is not null`;
    expect(await run(context(withFunction(checked)), "BS112")).toEqual([]);
    const revoked = withFunction(open, { ...definer, execute: [] });
    expect(await run(context(revoked), "BS112")).toEqual([]);
  });

  it("flags storage inserts without the upsert policies (BS113)", async () => {
    const file = (text: string) => ({
      sqlFiles: [{ path: "supabase/schemas/storage.sql", text }],
    });
    const insert =
      "create policy logos_insert on storage.objects for insert to authenticated with check (bucket_id = 'logos');";
    expect(await run(context(base, file(insert)), "BS113")).toMatchObject([
      { message: expect.stringContaining("no select or update policy") },
    ]);
    const trio = `${insert}\ncreate policy logos_read on storage.objects for select to authenticated using (bucket_id = 'logos');\ncreate policy logos_update on storage.objects for update to authenticated using (bucket_id = 'logos');`;
    expect(await run(context(base, file(trio)), "BS113")).toEqual([]);
  });

  it("flags policy helpers that read user_metadata (BS114)", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy({
          using: "private.is_admin()",
          functions: ["private.is_admin"],
        }),
      ];
    });
    const sqlFiles = [
      {
        path: "supabase/schemas/private.sql",
        text: "create function private.is_admin() returns boolean language sql as $$ select (auth.jwt() -> 'user_metadata' ->> 'admin')::boolean $$;",
      },
    ];
    expect(await run(context(snap, { sqlFiles }), "BS114")).toMatchObject([
      { severity: "error", target: "private.is_admin" },
    ]);
  });

  it("flags zero-argument helpers called without select (BS215)", async () => {
    const bare = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy({
          using: "(organization_id = better_supabase.current_tenant_id())",
          functions: ["better_supabase.current_tenant_id"],
        }),
      ];
    });
    expect(await run(context(bare), "BS215")).toMatchObject([
      {
        message: expect.stringContaining(
          "(select better_supabase.current_tenant_id())",
        ),
      },
    ]);
    const wrapped = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy({
          using:
            "(organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id))",
          functions: ["better_supabase.current_tenant_id"],
        }),
      ];
    });
    expect(await run(context(wrapped), "BS215")).toEqual([]);
  });
});
