import { describe, expect, it, vi } from "vitest";

import type {
  AuthorizationRequest,
  RequestMemo,
} from "../../../src/core/authorizer.ts";

import { permissionsAuthorizer } from "../../../src/blocks/permissions/authorizer.ts";

const permissions = {
  invoices: { read: "invoices.read", write: "invoices.write" },
  "work-items": { read: "work-items.read", delete: "work-items.delete" },
} as const;

type Key = "invoices.read" | "invoices.write" | "work-items.read";

const requestFor = (
  action: Key,
  claims: Record<string, unknown> | undefined,
  tenant: string | null = "org-1",
): AuthorizationRequest<Key> => ({
  subject: {
    type: "user",
    id: "user-1",
    properties: claims === undefined ? {} : { claims },
  },
  action,
  resource: { type: "invoices" },
  context: tenant === null ? {} : { tenant },
});

const memo = (): RequestMemo => {
  const seen = new Map<string, Promise<unknown>>();

  return {
    once: <T>(key: string, load: () => Promise<T>): Promise<T> => {
      if (!seen.has(key)) {
        seen.set(key, load());
      }

      // SAFETY: the test stores the promise of the load for each key.
      return seen.get(key) as Promise<T>;
    },
  };
};

describe("permissionsAuthorizer", () => {
  it("grants from the token's keys for the tenant", async () => {
    const authorizer = permissionsAuthorizer({ permissions });
    const claims = { permissions: { "org-1": ["invoices.*"] } };

    await expect(
      authorizer.evaluate(requestFor("invoices.write", claims)),
    ).resolves.toEqual({ outcome: "granted" });

    await expect(
      authorizer.evaluate(requestFor("work-items.read", claims)),
    ).resolves.toMatchObject({ outcome: "denied" });
  });

  it("denies without a tenant, a claim or a loader", async () => {
    const authorizer = permissionsAuthorizer({ permissions });

    await expect(
      authorizer.evaluate(requestFor("invoices.read", undefined)),
    ).resolves.toMatchObject({ outcome: "denied" });

    await expect(
      authorizer.evaluate(
        requestFor("invoices.read", { permissions: { "org-1": ["*"] } }, null),
      ),
    ).resolves.toMatchObject({ outcome: "denied" });
  });

  it("loads once per subject and tenant when the token is truncated", async () => {
    const load = vi.fn(async () => ["invoices.read"]);
    const authorizer = permissionsAuthorizer({ permissions, load });
    const claims = { permissions: {}, permissions_truncated: true };
    const runtime = { memo: memo() };

    await expect(
      authorizer.evaluate(requestFor("invoices.read", claims), runtime),
    ).resolves.toEqual({ outcome: "granted" });

    await authorizer.evaluate(requestFor("invoices.write", claims), runtime);

    expect(load).toHaveBeenCalledOnce();
  });

  it("batches the loader across evaluations without a memo", async () => {
    const load = vi.fn(async () => ["invoices.read"]);
    const authorizer = permissionsAuthorizer({ permissions, load });

    const outcomes = await authorizer.evaluations?.([
      requestFor("invoices.read", undefined),
      requestFor("invoices.write", undefined),
    ]);

    expect(outcomes?.map((outcome) => outcome.outcome)).toEqual([
      "granted",
      "denied",
    ]);
    expect(load).toHaveBeenCalledOnce();
  });

  it("reads a renamed claim", async () => {
    const authorizer = permissionsAuthorizer({ permissions, claim: "perms" });

    await expect(
      authorizer.evaluate(
        requestFor("invoices.read", { perms: { "org-1": ["invoices.read"] } }),
      ),
    ).resolves.toEqual({ outcome: "granted" });
  });

  it("maps table operations to the generated keys", () => {
    const authorizer = permissionsAuthorizer({ permissions });

    expect(authorizer.forOperation?.("invoices", "list")).toBe("invoices.read");
    expect(authorizer.forOperation?.("invoices", "delete")).toBe(
      "invoices.write",
    );
    expect(authorizer.forOperation?.("work_items", "delete")).toBe(
      "work-items.delete",
    );
    expect(authorizer.forOperation?.("work_items", "create")).toBeUndefined();
    expect(authorizer.forOperation?.("unknown", "get")).toBeUndefined();
  });
});
