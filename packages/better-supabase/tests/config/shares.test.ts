import { describe, expect, it } from "vitest";

import type { RequestContext } from "../../src/core/plugin.ts";
import type { SchemaMeta } from "../../src/index.ts";

import { functionSharesMeta } from "../../src/cli/gen/function-meta.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { resolveShares, restatedShares } from "../../src/config/shares.ts";
import { defineAuthorizationHooks } from "../../src/core/contracts/authorization-hooks.ts";
import { tenantShareFor } from "../../src/server/tenant-share.ts";
import { stubProvider } from "../fixtures/authorization-provider.ts";

const provider = {
  ...stubProvider,
  tables: {
    "public.customers": { share: "tenant" as const, permissions: ["crm.read"] },
  },
  sharedFunctions: {
    "api.customer_payload": {
      tables: ["public.customers"],
      permissions: ["crm.read"],
    },
  },
};

describe("resolveShares", () => {
  it("keeps an app table the provider does not declare", () => {
    const shares = resolveShares({
      authorization: provider,
      shares: {
        tables: {
          "public.notes": { share: "tenant", permissions: ["notes.read"] },
        },
      },
    });

    expect(shares.tables["public.notes"]).toEqual({
      source: "app",
      share: { share: "tenant", permissions: ["notes.read"] },
    });
    expect(shares.tables["public.customers"]?.source).toBe("provider");
    expect(shares.conflicts).toEqual([]);
  });

  it("drops an identical app entry and reports a disagreement", () => {
    const config = {
      authorization: provider,
      shares: {
        tables: {
          "public.customers": {
            share: "tenant" as const,
            permissions: ["crm.read"],
          },
          "public.orders": {
            share: "row" as const,
            permissions: ["orders.read"],
          },
        },
        functions: {
          "api.customer_payload": {
            tables: ["public.invoices"],
            permissions: ["crm.read"],
          },
        },
      },
    };

    const shares = resolveShares(config);

    expect(shares.tables["public.customers"]?.source).toBe("provider");
    expect(shares.tables["public.orders"]?.source).toBe("app");
    expect(shares.functions["api.customer_payload"]?.share.tables).toEqual([
      "public.customers",
    ]);
    expect(shares.conflicts).toEqual([
      { kind: "function", name: "api.customer_payload" },
    ]);
    expect(restatedShares(config)).toEqual([
      {
        path: "shares.tables.public.customers",
        value: { share: "tenant", permissions: ["crm.read"] },
      },
    ]);
  });

  it("writes an app function into the generated meta with no provider entry", () => {
    const config = resolveConfig(
      {
        shares: {
          functions: {
            "api.note_payload": {
              tables: ["public.notes"],
              permissions: ["notes.read"],
            },
          },
        },
      },
      "/project",
    );

    expect(functionSharesMeta(config, []).functionShares).toEqual({
      note_payload: {
        schema: "api",
        tables: ["public.notes"],
        permissions: ["notes.read"],
      },
    });
  });
});

describe("a table shared only by the app", () => {
  // SAFETY: tenantShareOf reads only tables.<key>.share.
  const meta = {
    tables: {
      notes: { share: { kind: "tenant", permissions: ["notes.read"] } },
      contacts: {},
    },
  } as unknown as SchemaMeta;

  const share = tenantShareFor({
    meta,
    hooks: defineAuthorizationHooks({
      apiVersion: 1,
      name: "app",
      shareKey: () => "grant",
    }),
    authorizer: undefined,
  });

  // SAFETY: the share decision reads the generated meta before the context.
  const ctx = { db: { $context: {} as RequestContext } };

  it("shares the read when the generated meta lists the table", async () => {
    await expect(share(ctx, ["notes"], "org-1")).resolves.toEqual({
      kind: "shared",
      key: "org-1:grant",
    });
  });

  it("names shares.tables when the generated meta does not list the table", async () => {
    const refused = await share(ctx, ["contacts"], "org-1");

    expect(refused).toMatchObject({
      kind: "refused",
      error: { message: expect.stringContaining("shares.tables") },
    });
  });
});
