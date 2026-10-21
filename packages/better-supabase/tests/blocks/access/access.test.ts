import { describe, expect, it } from "vitest";

import { createAccess } from "../../../src/blocks/access/index.ts";

function fakeTransport(result: unknown) {
  const calls: [string, string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([schema, fn, { ...args }]);

        return Promise.resolve(result);
      },
    },
  };
}

describe("createAccess", () => {
  it("calls my_permissions in the block's tenant with the unique keys", async () => {
    const fake = fakeTransport(["customers.read"]);
    const access = createAccess({ transport: fake.transport, tenant: "org-1" });

    const set = await access
      .permissions(["customers.read", "customers.write", "customers.read"])
      .orThrow();

    expect(set).toEqual({ tenant: "org-1", keys: ["customers.read"] });
    expect(fake.calls).toEqual([
      [
        "better_supabase",
        "my_permissions",
        { tenant: "org-1", keys: ["customers.read", "customers.write"] },
      ],
    ]);
  });

  it("lists every key without a list, and skips the call for an empty one", async () => {
    const fake = fakeTransport(["*"]);
    const access = createAccess({ transport: fake.transport, tenant: "org-1" });

    expect(await access.permissions().orThrow()).toEqual({
      tenant: "org-1",
      keys: ["*"],
    });
    expect(await access.permissions([]).orThrow()).toEqual({
      tenant: "org-1",
      keys: [],
    });
    expect(fake.calls.map(([, , args]) => args)).toEqual([
      { tenant: "org-1", keys: null },
    ]);
  });

  it("answers can and flags, and takes a tenant per call", async () => {
    const fake = fakeTransport(["invoices.write"]);
    const access = createAccess({ transport: fake.transport });

    expect(
      await access.can("invoices.write", { tenant: "org-2" }).orThrow(),
    ).toBe(true);
    expect(
      await access
        .flags(
          { edit: "invoices.write", void: "invoices.void" },
          { tenant: "org-2" },
        )
        .orThrow(),
    ).toEqual({ canEdit: true, canVoid: false });
  });

  it("fails with TENANT_REQUIRED without a tenant", async () => {
    const fake = fakeTransport([]);
    const result = await createAccess({ transport: fake.transport }).can("x");

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.hint).toBe("TENANT_REQUIRED");
    expect(fake.calls).toEqual([]);
  });
});
