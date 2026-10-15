import { describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../../src/client/bind.ts";

import { createOrganizationsController } from "../../../src/blocks/organizations/client.ts";
import { DbException } from "../../../src/core/db-exception.ts";
import { dbError } from "../../../src/core/errors.ts";
import {
  failed,
  fakeAuth,
  flush,
  mount,
  resolved,
  USER,
  SIGNED_OUT,
  OTHER,
} from "../../fixtures/ports.ts";

const withTenant = (tenant: string, id = USER): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id, tenant_id: tenant },
});

function setup(
  options: {
    initial?: readonly { id: string }[];
    activeId?: string | null;
  } = {},
) {
  const auth = fakeAuth(withTenant("org-1"));
  const load = vi.fn(async () => [{ id: "org-1" }, { id: "org-2" }]);
  const switchOrganization = vi.fn(() =>
    resolved({ organizationId: "org-2", refresh: true }),
  );
  const onSwitched = vi.fn(() => {
    auth.set(withTenant("org-2"));
  });
  const controller = createOrganizationsController({
    client: { switch: switchOrganization },
    auth,
    load,
    onSwitched,
    ...options,
  });
  return { auth, load, switchOrganization, onSwitched, controller };
}

describe("createOrganizationsController", () => {
  it("loads the organizations and follows the tenant claim", async () => {
    const { auth, load, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().organizations).toEqual([{ id: "org-1" }, { id: "org-2" }]);
    expect(view().activeId).toBe("org-1");
    auth.set(withTenant("org-2"));
    expect(view().activeId).toBe("org-2");
    expect(load).toHaveBeenCalledTimes(1);
    auth.set(withTenant("org-3", OTHER));
    expect(load).toHaveBeenCalledTimes(2);
    unmount();
  });

  it("switches, runs onSwitched and loads again", async () => {
    const { load, switchOrganization, onSwitched, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    const switching = view().switchTo("org-2");
    expect(view().switching).toBe("org-2");
    expect(await switching).toMatchObject({
      ok: true,
      data: { organizationId: "org-2", refresh: true },
    });
    expect(switchOrganization).toHaveBeenCalledWith("org-2");
    expect(onSwitched).toHaveBeenCalledWith({
      organizationId: "org-2",
      refresh: true,
    });
    expect(view().activeId).toBe("org-2");
    expect(view().switching).toBeUndefined();
    expect(load).toHaveBeenCalledTimes(2);
    unmount();
  });

  it("keeps the errors of a switch and a load", async () => {
    const { load, switchOrganization, onSwitched, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    switchOrganization.mockReturnValueOnce(failed("not a member"));
    expect((await view().switchTo("org-9")).ok).toBe(false);
    expect(view().error?.message).toBe("not a member");
    expect(view().switching).toBeUndefined();

    onSwitched.mockImplementationOnce(() => {
      throw new Error("refresh failed");
    });
    expect(await view().switchTo("org-2")).toMatchObject({
      ok: false,
      error: { message: "refresh failed" },
    });
    expect(view().error).toMatchObject({ message: "refresh failed" });

    load.mockRejectedValueOnce(new DbException(dbError("forbidden", "nope")));
    await view().refresh();
    expect(view().error).toMatchObject({ kind: "forbidden" });
    unmount();
  });

  it("starts from the server's rows and active organization", async () => {
    const auth = fakeAuth({ status: "loading", user: null, claims: null });
    const load = vi.fn(async () => [{ id: "org-1" }]);
    const controller = createOrganizationsController({
      client: {
        switch: () => resolved({ organizationId: "x", refresh: false }),
      },
      auth,
      load,
      onSwitched: () => undefined,
      initial: [{ id: "org-1" }],
      activeId: "org-1",
    });
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().activeId).toBe("org-1");
    expect(view().organizations).toEqual([{ id: "org-1" }]);
    auth.set(withTenant("org-1"));
    expect(load).not.toHaveBeenCalled();
    await view().switchTo("x");
    expect(view().activeId).toBe("org-1");
    auth.set(SIGNED_OUT);
    expect(view().activeId).toBe("x");
    auth.set(withTenant("org-1", OTHER));
    expect(load).toHaveBeenCalledTimes(2);
    unmount();
  });
});
