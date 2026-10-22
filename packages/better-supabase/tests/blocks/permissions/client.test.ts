import { describe, expect, it, vi } from "vitest";

import type { PermissionSet } from "../../../src/blocks/permissions/permissions-controller.ts";

import {
  batchPermissions,
  createPermissionsController,
} from "../../../src/blocks/permissions/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  mount,
  OTHER,
  resolved,
  signedIn,
} from "../../fixtures/ports.ts";

const source = (granted: readonly string[]) => ({
  permissions: vi.fn(
    (keys?: readonly string[], options?: { readonly tenant?: unknown }) =>
      resolved<PermissionSet>({
        tenant: String(options?.tenant),
        keys: (keys ?? []).filter((key) => granted.includes(key)),
      }),
  ),
});

describe("batchPermissions", () => {
  it("joins the calls of one tick per tenant and splits the answer", async () => {
    const inner = source(["a", "c"]);
    const batched = batchPermissions(inner);

    const [first, second, other] = await Promise.all([
      batched.permissions(["a", "b"], { tenant: "org-1" }),
      batched.permissions(["c"], { tenant: "org-1" }),
      batched.permissions(["a"], { tenant: "org-2" }),
    ]);

    expect(inner.permissions).toHaveBeenCalledTimes(2);
    expect(inner.permissions).toHaveBeenCalledWith(["a", "b", "c"], {
      tenant: "org-1",
    });
    expect(first.ok && first.data).toEqual({ tenant: "org-1", keys: ["a"] });
    expect(second.ok && second.data).toEqual({ tenant: "org-1", keys: ["c"] });
    expect(other.ok && other.data).toEqual({ tenant: "org-2", keys: ["a"] });
  });

  it("passes an error to every caller of the batch", async () => {
    const batched = batchPermissions({
      permissions: vi.fn(() => failed<PermissionSet>("down")),
    });

    const results = await Promise.all([
      batched.permissions(["a"], { tenant: "org-1" }),
      batched.permissions(["b"], { tenant: "org-1" }),
    ]);

    expect(results.map((result) => result.ok)).toEqual([false, false]);
  });

  it("passes a call without keys straight through", async () => {
    const inner = source(["a"]);

    await batchPermissions(inner).permissions(undefined, { tenant: "org-1" });

    expect(inner.permissions).toHaveBeenCalledWith(undefined, {
      tenant: "org-1",
    });
  });
});

describe("createPermissionsController errors", () => {
  it("keeps the error of a failed load", async () => {
    const { view, unmount } = mount(
      createPermissionsController({
        client: { permissions: () => failed<PermissionSet>("down") },
        auth: fakeAuth(),
        keys: ["a"],
        tenant: "org-1",
      }),
    );

    await flush();
    expect(view().error).toBeDefined();
    expect(view().permissions).toBeUndefined();
    unmount();
  });
});

describe("createPermissionsController", () => {
  it("loads the keys and loads again for another user", async () => {
    const auth = fakeAuth();
    const client = source(["invoices.write"]);

    const { view, unmount } = mount(
      createPermissionsController({
        client,
        auth,
        keys: ["invoices.write", "invoices.void"],
        tenant: "org-1",
      }),
    );

    await flush();
    expect(view().permissions).toEqual({
      tenant: "org-1",
      keys: ["invoices.write"],
    });

    auth.set(signedIn(OTHER));
    await flush();
    expect(client.permissions).toHaveBeenCalledTimes(2);
    unmount();
  });

  it("loads nothing without a tenant", async () => {
    const client = source([]);

    const { view, unmount } = mount(
      createPermissionsController({
        client,
        auth: fakeAuth(),
        keys: ["a"],
        tenant: undefined,
      }),
    );

    await flush();
    expect(view().permissions).toBeUndefined();
    expect(client.permissions).not.toHaveBeenCalled();
    unmount();
  });
});
