import { describe, expect, it } from "vitest";

import type { SecurityCatalog } from "../../../src/create/lite/index.ts";

import { previewFiles } from "../../../src/create/index.ts";
import {
  accessMatrix,
  readSecurityCatalog,
  verifyCatalog,
  verifyFiles,
} from "../../../src/create/lite/index.ts";
import { namedPreset, presetSpec } from "../../../src/preset/index.ts";

const table = (
  overrides: Partial<SecurityCatalog["tables"][number]> = {},
): SecurityCatalog["tables"][number] => ({
  schema: "public",
  name: "notes",
  rls: true,
  force: false,
  policies: [],
  grants: [{ grantee: "authenticated", privilege: "SELECT" }],
  ...overrides,
});

const catalogOf = (
  tables: SecurityCatalog["tables"],
  functions: SecurityCatalog["functions"] = [],
): SecurityCatalog => ({ tables, functions });

const codes = (catalog: SecurityCatalog, options = {}) =>
  verifyCatalog(catalog, options).map((each) => each.code);

describe("verifyCatalog", () => {
  it("passes a table with row level security and a scoped policy", () => {
    const catalog = catalogOf([
      table({
        policies: [
          {
            name: "read",
            command: "select",
            permissive: true,
            roles: ["authenticated"],
            using: "(owner_id = auth.uid())",
            check: null,
          },
        ],
      }),
    ]);

    expect(codes(catalog)).toEqual([]);
  });

  it("flags row level security off on a granted table", () => {
    expect(codes(catalogOf([table({ rls: false })]))).toEqual([
      "verify_rls_off",
    ]);
  });

  it("flags a write policy that is only true", () => {
    const catalog = catalogOf([
      table({
        policies: [
          {
            name: "any",
            command: "all",
            permissive: true,
            roles: ["authenticated"],
            using: "( true )",
            check: null,
          },
        ],
      }),
    ]);

    expect(codes(catalog)).toEqual(["verify_policy_true"]);
  });

  it("flags anon writes, PUBLIC grants and anon reading every row", () => {
    const catalog = catalogOf([
      table({
        grants: [
          { grantee: "anon", privilege: "SELECT" },
          { grantee: "anon", privilege: "INSERT" },
          { grantee: "public", privilege: "SELECT" },
        ],
        policies: [
          {
            name: "open",
            command: "select",
            permissive: true,
            roles: ["anon"],
            using: "true",
            check: null,
          },
        ],
      }),
    ]);

    expect(codes(catalog).toSorted()).toEqual([
      "verify_anon_reads_all",
      "verify_anon_write",
      "verify_public_grant",
    ]);
  });

  it("flags security definer functions without a search_path", () => {
    const catalog = catalogOf(
      [],
      [
        { schema: "public", name: "a", definer: true, searchPath: false },
        { schema: "public", name: "b", definer: true, searchPath: true },
        { schema: "public", name: "c", definer: false, searchPath: false },
      ],
    );

    expect(verifyCatalog(catalog)).toMatchObject([
      { code: "verify_definer_search_path", table: "public.a" },
    ]);
  });

  it("checks forced security and the tenant scope when asked", () => {
    expect(
      codes(catalogOf([table()]), {
        force: ["public.notes"],
        tenantScoped: ["public.notes"],
      }).toSorted(),
    ).toEqual(["verify_force_off", "verify_scope_missing"]);
  });
});

describe("accessMatrix", () => {
  it("reads reach from grants and policies", () => {
    const matrix = accessMatrix(
      catalogOf([
        table({
          grants: [
            { grantee: "authenticated", privilege: "SELECT" },
            { grantee: "authenticated", privilege: "INSERT" },
          ],
          policies: [
            {
              name: "read",
              command: "select",
              permissive: true,
              roles: ["authenticated"],
              using: "(owner_id = auth.uid())",
              check: null,
            },
          ],
        }),
      ]),
    );

    const reach = (role: string, command: string) =>
      matrix.find((cell) => cell.role === role && cell.command === command)
        ?.reach;

    expect(reach("authenticated", "select")).toBe("policy");
    expect(reach("authenticated", "insert")).toBe("denied");
    expect(reach("authenticated", "delete")).toBe("denied");
    expect(reach("anon", "select")).toBe("denied");
  });
});

describe("readSecurityCatalog", () => {
  it("reads JSON that arrives as text", () => {
    const catalog = readSecurityCatalog([
      { catalog: JSON.stringify({ tables: [], functions: [] }) },
    ]);

    expect(catalog).toEqual({ tables: [], functions: [] });
  });
});

describe("verifyFiles", () => {
  it("finds no error in the SaaS preset and keeps anon out of every table", async () => {
    const result = await verifyFiles(
      previewFiles(presetSpec(namedPreset("saas"))),
    );

    expect(result.issues.filter((each) => each.severity === "error")).toEqual(
      [],
    );

    const reached = result.matrix.filter(
      (cell) => cell.role === "anon" && cell.reach !== "denied",
    );

    expect(reached).toEqual([]);
  }, 60_000);
});
