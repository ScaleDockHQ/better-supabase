import { describe, expect, it } from "vitest";

import type { AuthorizationProvider } from "../../../src/config/index.ts";

import {
  keysOf,
  providerCalls,
} from "../../../src/cli/doctor/provider-calls.ts";

// SAFETY: the matcher reads only `functions` and `tenantScope`.
const provider = {
  tenantScope: "tenant",
  functions: {
    idsWith: "centrakit.authz_{scope}_ids_with({permission})",
    isPlatform: "centrakit.authz_is_platform({permission})",
  },
} as unknown as AuthorizationProvider;

// Texts as `pg_policies.qual` and `pg_get_functiondef` return them: Postgres
// casts every literal, adds `AS` aliases and parentheses, and drops the schema
// of a function on the search_path.
const DEPARSED = {
  schemaFile:
    "tenant_id IN (SELECT centrakit.authz_tenant_ids_with('tasks.read'))",
  cast: "(tenant_id IN ( SELECT centrakit.authz_tenant_ids_with('tasks.read'::text) AS authz_tenant_ids_with))",
  varying:
    "(tenant_id IN ( SELECT centrakit.authz_tenant_ids_with('tasks.read'::character varying) AS x))",
  unqualified:
    "(tenant_id IN ( SELECT authz_tenant_ids_with('tasks.read'::text) AS x))",
  quoted:
    "(tenant_id IN ( SELECT \"centrakit\".authz_tenant_ids_with('tasks.read'::text) AS x))",
  named:
    "(tenant_id IN ( SELECT centrakit.authz_tenant_ids_with(permission => 'tasks.read'::text) AS x))",
  array:
    "(tenant_id IN ( SELECT centrakit.authz_tenant_ids_with(ARRAY['tasks.read'::text, 'tasks.write'::text]) AS x))",
  arrayLiteral:
    "(tenant_id IN ( SELECT centrakit.authz_tenant_ids_with('{tasks.read,tasks.write}'::text[]) AS x))",
  platform:
    "(centrakit.authz_is_platform('platform.read'::text) OR tenant_id IN ( SELECT centrakit.authz_tenant_ids_with('tasks.read'::text) AS x))",
};

describe("providerCalls", () => {
  it.each([
    "schemaFile",
    "cast",
    "varying",
    "unqualified",
    "quoted",
    "named",
  ] as const)("reads one key from the %s form", (form) => {
    expect(providerCalls(provider, DEPARSED[form])).toEqual([
      { key: "tasks.read", scope: "tenant" },
    ]);
  });

  it.each(["array", "arrayLiteral"] as const)(
    "reads every key of the %s form",
    (form) => {
      expect(
        providerCalls(provider, DEPARSED[form]).map((call) => call.key),
      ).toEqual(["tasks.read", "tasks.write"]);
    },
  );

  it("reads a cast key of isPlatform", () => {
    expect(providerCalls(provider, DEPARSED.platform)).toEqual([
      { key: "tasks.read", scope: "tenant" },
      { key: "platform.read", scope: "platform" },
    ]);
  });

  it("unescapes a doubled quote", () => {
    expect(keysOf("'it''s'::text")).toEqual(["it's"]);
  });
});
