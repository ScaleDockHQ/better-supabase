import { describe, expect, it, vi } from "vitest";

import type {
  BlockTransport,
  ServicePrincipalAuthAdmin,
} from "../../../src/blocks/service-principals/index.ts";

import {
  createServicePrincipals,
  SERVICE_PRINCIPAL_CLAIM,
} from "../../../src/blocks/service-principals/index.ts";

const AT = "2026-10-14T07:00:00.000Z";

function transport(
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const call = vi.fn(
    async (_schema: string, fn: string, args: Record<string, unknown>) =>
      answer(fn, args),
  );
  const value: BlockTransport = { call };
  return { call, transport: value };
}

function admin(error: string | null = null) {
  const createUser = vi.fn<ServicePrincipalAuthAdmin["createUser"]>(async () =>
    error === null
      ? { data: { user: { id: "sp-1" } }, error: null }
      : { data: { user: null }, error: { message: error } },
  );
  const deleteUser = vi.fn<ServicePrincipalAuthAdmin["deleteUser"]>(
    async () => ({ error: null }),
  );
  return { createUser, deleteUser };
}

const REGISTERED = {
  id: "sp-1",
  tenant: "org-1",
  name: "Automations",
  role: "member",
  isDefault: true,
};

describe("createServicePrincipals", () => {
  it("creates a banned auth user, then registers it with its role", async () => {
    const auth = admin();
    const { call, transport: t } = transport(() => REGISTERED);
    const principals = createServicePrincipals({ transport: t, admin: auth });
    const created = await principals
      .create("org-1", "Automations", "member", {
        default: true,
        createdBy: "u-1",
      })
      .orThrow();
    expect(created).toEqual({
      id: "sp-1",
      organizationId: "org-1",
      name: "Automations",
      role: "member",
      isDefault: true,
      fields: {},
    });
    const attributes = auth.createUser.mock.calls[0]?.[0];
    expect(attributes?.email).toMatch(/@service-principals\.invalid$/);
    expect(attributes?.ban_duration).toBe("876000h");
    expect(attributes?.app_metadata).toEqual({
      [SERVICE_PRINCIPAL_CLAIM]: true,
      organization_id: "org-1",
    });
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "register_service_principal",
      {
        principal: "sp-1",
        tenant: "org-1",
        name: "Automations",
        role: "member",
        is_default: true,
        created_by: "u-1",
      },
    );
    expect(auth.deleteUser).not.toHaveBeenCalled();
  });

  it("deletes the auth user when the registration is refused", async () => {
    const auth = admin();
    const { transport: t } = transport(() => {
      throw Object.assign(new Error("You may not manage service principals"), {
        code: "42501",
        hint: "SERVICE_PRINCIPAL_FORBIDDEN",
      });
    });
    const principals = createServicePrincipals({ transport: t, admin: auth });
    const result = await principals.create("org-1", "Bot", "owner", {
      createdBy: "u-2",
    });
    expect(!result.ok && result.error.kind).toBe("forbidden");
    expect(auth.deleteUser).toHaveBeenCalledWith("sp-1");
  });

  it("reports an Auth refusal without calling the database", async () => {
    const auth = admin("email exists");
    const { call, transport: t } = transport(() => REGISTERED);
    const principals = createServicePrincipals({ transport: t, admin: auth });
    const result = await principals.create("org-1", "Bot", "member");
    expect(!result.ok && result.error.message).toContain("email exists");
    expect(call).not.toHaveBeenCalled();
  });

  it("changes roles, disables, resolves the default and lists", async () => {
    const { call, transport: t } = transport((fn) => {
      switch (fn) {
        case "default_service_principal":
          return "sp-1";
        case "service_principals_list":
          return [
            {
              id: "sp-1",
              name: "Automations",
              role: "member",
              isDefault: true,
              createdBy: null,
              createdAt: AT,
              disabledAt: null,
            },
          ];
        default:
          return true;
      }
    });
    const principals = createServicePrincipals({
      transport: t,
      admin: admin(),
    });
    expect(await principals.setRole("sp-1", "admin").orThrow()).toBe(true);
    expect(
      await principals.disable("sp-1", { createdBy: "u-1" }).orThrow(),
    ).toBe(true);
    expect(await principals.defaultFor("org-1").orThrow()).toBe("sp-1");
    const [listed] = await principals.list("org-1").orThrow();
    expect(listed?.createdAt.toString()).toBe("2026-10-14T07:00:00Z");
    expect(listed?.disabledAt).toBeNull();
    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "set_service_principal_role",
        { principal: "sp-1", role: "admin", created_by: null },
      ],
      ["disable_service_principal", { principal: "sp-1", created_by: "u-1" }],
      ["default_service_principal", { tenant: "org-1" }],
      ["service_principals_list", { tenant: "org-1" }],
    ]);
  });
});
