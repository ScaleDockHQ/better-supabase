import { describe, expect, it, vi } from "vitest";

import type { InvitationSent } from "../../../src/blocks/organizations/organizations.ts";
import type { AuthSnapshot } from "../../../src/client/bind.ts";

import {
  createInvitationsController,
  createMembersController,
  createOrganizationsController,
} from "../../../src/blocks/organizations/client.ts";
import { DbException } from "../../../src/core/db-exception.ts";
import { dbError } from "../../../src/core/errors.ts";
import {
  failed,
  fakeAuth,
  flush,
  held,
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
    expect(load).toHaveBeenCalledOnce();
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

type Role = "owner" | "admin" | "member";

function members(
  options: {
    organizationId?: string | null;
    initial?: readonly { userId: string; role: Role }[];
  } = {},
) {
  const auth = fakeAuth();

  const rows = [
    { userId: "u-1", role: "owner" as Role },
    { userId: "u-2", role: "member" as Role },
  ];

  const load = vi.fn(async (_organizationId: string) => rows);

  const updateMemberRole = vi.fn(
    (_organizationId: string, _userId: string, _role: string) =>
      resolved(true as const),
  );

  const removeMember = vi.fn((_organizationId: string, _userId: string) =>
    resolved(true as const),
  );

  const onChanged = vi.fn();

  const controller = createMembersController<{ userId: string; role: Role }>({
    client: { updateMemberRole, removeMember },
    auth,
    organizationId: "org-1",
    load,
    onChanged,
    ...options,
  });

  return {
    auth,
    rows,
    load,
    updateMemberRole,
    removeMember,
    onChanged,
    controller,
  };
}

describe("createMembersController", () => {
  it("loads the members once signed in, and waits without an organization", async () => {
    const { load, controller } = members();
    const { view, unmount } = mount(controller);
    await flush();
    expect(load).toHaveBeenCalledWith("org-1");
    expect(view().members).toHaveLength(2);
    unmount();

    const idle = members({ organizationId: null });
    const idleView = mount(idle.controller);
    await flush();
    expect(idle.load).not.toHaveBeenCalled();
    expect(await idleView.view().setRole("u-2", "admin")).toMatchObject({
      ok: false,
      error: { kind: "invalid_input" },
    });
    expect(await idleView.view().remove("u-2")).toMatchObject({ ok: false });
    await idleView.view().refresh();
    idleView.unmount();
  });

  it("shows a role change at once and runs onChanged after it committed", async () => {
    const { updateMemberRole, onChanged, controller } = members();
    const { view, unmount } = mount(controller);
    await flush();
    const write = held(true as const);
    updateMemberRole.mockReturnValueOnce(write.result);
    const changing = view().setRole("u-2", "admin");
    expect(view().members?.[1]?.role).toBe("admin");
    expect(view().pending).toEqual(["u-2"]);
    write.release();
    expect((await changing).ok).toBe(true);
    expect(view().pending).toEqual([]);
    expect(updateMemberRole).toHaveBeenCalledWith("org-1", "u-2", "admin");
    expect(onChanged).toHaveBeenCalledWith({
      kind: "role",
      organizationId: "org-1",
      userId: "u-2",
      role: "admin",
    });
    unmount();
  });

  it("puts the role back and keeps the error when the change fails", async () => {
    const { updateMemberRole, onChanged, controller } = members();
    const { view, unmount } = mount(controller);
    await flush();
    updateMemberRole.mockReturnValueOnce(failed("not allowed"));
    expect((await view().setRole("u-2", "admin")).ok).toBe(false);
    expect(view().members?.[1]?.role).toBe("member");
    expect(view().error?.message).toBe("not allowed");
    expect(onChanged).not.toHaveBeenCalled();
    unmount();
  });

  it("removes a member, then loads the table again", async () => {
    const { load, removeMember, onChanged, controller } = members();
    const { view, unmount } = mount(controller);
    await flush();
    load.mockResolvedValueOnce([{ userId: "u-1", role: "owner" }]);
    expect((await view().remove("u-2")).ok).toBe(true);
    expect(removeMember).toHaveBeenCalledWith("org-1", "u-2");
    expect(onChanged).toHaveBeenCalledWith({
      kind: "removed",
      organizationId: "org-1",
      userId: "u-2",
    });
    expect(view().members).toEqual([{ userId: "u-1", role: "owner" }]);
    expect(load).toHaveBeenCalledTimes(2);

    removeMember.mockReturnValueOnce(failed("last owner"));
    expect((await view().remove("u-1")).ok).toBe(false);
    expect(view().members).toHaveLength(1);
    expect(view().error?.message).toBe("last owner");
    unmount();
  });

  it("starts from the server's rows and keeps load and onChanged errors", async () => {
    const { load, onChanged, controller } = members({
      initial: [{ userId: "u-9", role: "admin" }],
    });

    const { view, unmount } = mount(controller);
    await flush();
    expect(load).not.toHaveBeenCalled();
    expect(view().members).toEqual([{ userId: "u-9", role: "admin" }]);

    onChanged.mockRejectedValueOnce(new Error("session refresh failed"));
    expect((await view().setRole("u-9", "member")).ok).toBe(true);
    expect(view().error?.message).toBe("session refresh failed");

    load.mockRejectedValueOnce(new DbException(dbError("forbidden", "nope")));
    await view().refresh();
    expect(view().error).toMatchObject({ kind: "forbidden" });
    unmount();
  });
});

const sent = (email: string): InvitationSent => ({
  invitation: {
    id: "inv-1",
    organizationId: "org-1",
    email,
    role: "member",
    expiresAt: Temporal.Instant.from("2026-10-23T00:00:00Z"),
    organization: null,
    prefill: {},
    inviter: null,
    extra: {},
    fields: {},
  },
  token: "token-1",
  resent: false,
});

function invitations(
  options: {
    organizationId?: string | null;
    initial?: readonly { id: string }[];
  } = {},
) {
  const auth = fakeAuth();
  const load = vi.fn(async (_organizationId: string) => [{ id: "inv-0" }]);

  const invite = vi.fn(
    (request: {
      readonly email: string;
      readonly organizationId: string | null;
    }) => resolved(sent(request.email)),
  );

  const revokeInvitation = vi.fn((_id: string) => resolved(true));
  const onChanged = vi.fn();

  const controller = createInvitationsController<{ id: string }>({
    client: { invite, revokeInvitation },
    auth,
    organizationId: "org-1",
    load,
    onChanged,
    ...options,
  });

  return { load, invite, revokeInvitation, onChanged, controller };
}

describe("createInvitationsController", () => {
  it("sends an invitation, keeps its token and loads the list again", async () => {
    const { load, invite, onChanged, controller } = invitations();
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().invitations).toEqual([{ id: "inv-0" }]);

    const inviting = view().invite({
      email: "ada@example.com",
      role: "member",
    });

    expect(view().inviting).toBe(true);
    const result = await inviting;
    expect(result.ok).toBe(true);
    expect(invite).toHaveBeenCalledWith({
      email: "ada@example.com",
      role: "member",
      organizationId: "org-1",
    });
    expect(view().inviting).toBe(false);
    expect(view().sent?.token).toBe("token-1");
    expect(onChanged).toHaveBeenCalledWith(
      expect.objectContaining({ kind: "invited", organizationId: "org-1" }),
    );
    expect(load).toHaveBeenCalledTimes(2);
    view().clear();
    expect(view().sent).toBeUndefined();
    unmount();
  });

  it("keeps a failed invitation's error and revokes one", async () => {
    const { invite, revokeInvitation, onChanged, controller } = invitations({
      initial: [{ id: "inv-0" }],
    });

    const { view, unmount } = mount(controller);
    await flush();
    invite.mockReturnValueOnce(failed("already invited"));
    expect((await view().invite({ email: "a@b.c", role: "member" })).ok).toBe(
      false,
    );
    expect(view().error?.message).toBe("already invited");
    expect(view().inviting).toBe(false);

    const revoking = view().revoke("inv-0");
    expect(view().revoking).toEqual(["inv-0"]);
    expect((await revoking).ok).toBe(true);
    expect(revokeInvitation).toHaveBeenCalledWith("inv-0");
    expect(view().revoking).toEqual([]);
    expect(onChanged).toHaveBeenCalledWith({
      kind: "revoked",
      organizationId: "org-1",
      invitationId: "inv-0",
    });

    revokeInvitation.mockReturnValueOnce(failed("gone"));
    expect((await view().revoke("inv-0")).ok).toBe(false);
    expect(view().error?.message).toBe("gone");
    unmount();
  });

  it("waits without an organization and keeps load and onChanged errors", async () => {
    const idle = invitations({ organizationId: null });
    const idleView = mount(idle.controller);
    await flush();
    expect(idle.load).not.toHaveBeenCalled();
    expect(
      (await idleView.view().invite({ email: "a@b.c", role: "member" })).ok,
    ).toBe(false);
    expect((await idleView.view().revoke("inv-0")).ok).toBe(false);
    await idleView.view().refresh();
    idleView.unmount();

    const { load, onChanged, controller } = invitations();
    const { view, unmount } = mount(controller);
    await flush();
    load.mockRejectedValueOnce(new Error("load failed"));
    await view().refresh();
    expect(view().error?.message).toBe("load failed");
    onChanged.mockRejectedValueOnce(new Error("step failed"));
    await view().invite({ email: "a@b.c", role: "member" });
    expect(view().error?.message).toBe("step failed");
    unmount();
  });
});
