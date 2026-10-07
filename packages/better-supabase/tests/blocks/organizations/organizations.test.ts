import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/blocks/organizations/index.ts";
import type { BlockEvent } from "../../../src/core/block-events.ts";

import {
  createOrganizations,
  rpcTransport,
  sqlTransport,
} from "../../../src/blocks/organizations/index.ts";
import { EventHub } from "../../../src/core/events.ts";

interface Call {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function fake(results: Record<string, unknown>): {
  transport: BlockTransport;
  calls: Call[];
} {
  const calls: Call[] = [];
  return {
    calls,
    transport: {
      call(schema, fn, args) {
        calls.push({ schema, fn, args });
        const value = results[fn];
        return value instanceof Error
          ? Promise.reject(value)
          : Promise.resolve(value ?? null);
      },
    },
  };
}

const invitationRow = {
  id: "inv-1",
  tenant: "org-1",
  email: "ada@example.com",
  role: "member",
  expires_at: "2026-10-10T12:00:00+00:00",
  invited_by: "user-1",
  prefill: { name: "Ada" },
  token: "secret",
};

function pgError(code: string, hint: string): Error {
  return Object.assign(new Error("refused"), { code, hint });
}

describe("createOrganizations", () => {
  it("calls the block functions in the module schemas", async () => {
    const { transport, calls } = fake({
      create_organization: "org-1",
      invite_member: invitationRow,
    });
    const organizations = createOrganizations({
      transport,
      schema: { organizations: "public", invitations: "block" },
    });
    expect(
      await organizations.create({ name: "Acme", slug: "acme" }),
    ).toMatchObject({
      ok: true,
      data: { id: "org-1" },
    });
    await organizations.invite({
      organizationId: "org-1",
      email: "ada@example.com",
      role: "member",
    });
    expect(calls).toEqual([
      {
        schema: "public",
        fn: "create_organization",
        args: { attrs: { name: "Acme", slug: "acme" } },
      },
      {
        schema: "block",
        fn: "invite_member",
        args: {
          tenant: "org-1",
          invitee_email: "ada@example.com",
          invitee_role: "member",
          valid_for: undefined,
          prefill: undefined,
        },
      },
    ]);
  });

  it("passes the owner for the service role", async () => {
    const { transport, calls } = fake({ create_organization: "org-1" });
    await createOrganizations({ transport }).create(
      { name: "Acme" },
      { ownerId: "user-9" },
    );
    expect(calls[0]).toMatchObject({
      schema: "better_supabase",
      args: { attrs: { name: "Acme", owner_id: "user-9" } },
    });
  });

  it("maps database errors and keeps the block code as the hint", async () => {
    const { transport } = fake({
      remove_member: pgError("42501", "ORGANIZATION_FORBIDDEN"),
    });
    const result = await createOrganizations({ transport }).removeMember(
      "organization",
      "user",
    );
    expect(result).toMatchObject({
      ok: false,
      error: {
        kind: "forbidden",
        code: "42501",
        hint: "ORGANIZATION_FORBIDDEN",
      },
    });
  });

  it("applies custom error mappers first", async () => {
    const { transport } = fake({
      leave_organization: pgError("P0001", "ORGANIZATION_OWNER_REQUIRED"),
    });
    const result = await createOrganizations({
      transport,
      errorMappers: [
        (raw, fallback) =>
          raw.hint === "ORGANIZATION_OWNER_REQUIRED"
            ? { ...fallback, message: "Transfer ownership first" }
            : undefined,
      ],
    }).leave("organization");
    expect(result).toMatchObject({
      ok: false,
      error: { message: "Transfer ownership first" },
    });
  });

  it("turns other failures into unexpected errors", async () => {
    const { transport } = fake({ mark_used: new Error("socket closed") });
    const result = await createOrganizations({ transport }).markUsed(
      "organization",
    );
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "unexpected", message: "socket closed" },
    });
  });

  it("refuses an invitation when canInvite says no", async () => {
    const { transport, calls } = fake({});
    const canInvite = vi.fn(() => false);
    const result = await createOrganizations({ transport, canInvite }).invite({
      organizationId: "org-1",
      email: "ada@example.com",
      role: "admin",
    });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "forbidden", hint: "INVITATION_FORBIDDEN" },
    });
    expect(canInvite).toHaveBeenCalledWith({
      organizationId: "org-1",
      email: "ada@example.com",
      role: "admin",
    });
    expect(calls).toEqual([]);
  });

  it("hands the token to onInvite and emits the block event", async () => {
    const { transport } = fake({
      invite_member: invitationRow,
      resend_invitation: { ...invitationRow, token: "fresh" },
    });
    const events = new EventHub();
    const seen: BlockEvent[] = [];
    events.on("block", (event) => seen.push(event));
    const onInvite = vi.fn();
    const organizations = createOrganizations({
      transport,
      events,
      actorId: "user-1",
      onInvite,
    });
    const result = await organizations.invite({
      organizationId: "org-1",
      email: "ada@example.com",
      role: "member",
    });
    expect(result.ok && result.data.token).toBe("secret");
    expect(result.ok && result.data.invitation).toMatchObject({
      id: "inv-1",
      organizationId: "org-1",
      invitedBy: "user-1",
      prefill: { name: "Ada" },
    });
    expect(result.ok && result.data.invitation.expiresAt.toString()).toBe(
      "2026-10-10T12:00:00Z",
    );
    await organizations.resendInvitation("inv-1");
    expect(
      onInvite.mock.calls.map(([sent]) => [sent.token, sent.resent]),
    ).toEqual([
      ["secret", false],
      ["fresh", true],
    ]);
    expect(seen.map((event) => event.type)).toEqual([
      "invitation.created",
      "invitation.resent",
    ]);
    expect(seen[0]).toMatchObject({
      subject: "invitations/inv-1",
      tenant: "org-1",
      actorId: "user-1",
      data: { invitationId: "inv-1", email: "ada@example.com" },
    });
    expect(JSON.stringify(seen[0]?.data)).not.toContain("secret");
  });

  it("returns an error when onInvite throws", async () => {
    const { transport } = fake({ invite_member: invitationRow });
    const result = await createOrganizations({
      transport,
      onInvite: () => {
        throw new Error("mail down");
      },
    }).invite({ organizationId: "org-1", email: "a@b.c", role: "member" });
    expect(result).toMatchObject({
      ok: false,
      error: { message: "mail down" },
    });
  });

  it("emits organization events after each change", async () => {
    const { transport } = fake({
      update_organization: true,
      delete_organization: true,
      update_member_role: true,
      transfer_ownership: true,
      switch_organization: { organization_id: "org-1", refresh: true },
      accept_invitation: "org-1",
      revoke_invitation: false,
    });
    const events = new EventHub();
    const seen: string[] = [];
    events.on("block", (event) => seen.push(event.type));
    const organizations = createOrganizations({
      transport,
      events,
      actorId: "user-1",
    });
    await organizations.update("org-1", { name: "Acme" });
    await organizations.updateMemberRole("org-1", "user-2", "admin");
    await organizations.transferOwnership("org-1", "user-2");
    expect(await organizations.switch("org-1")).toMatchObject({
      ok: true,
      data: { organizationId: "org-1", refresh: true },
    });
    expect(await organizations.acceptInvitation("token")).toMatchObject({
      ok: true,
      data: { organizationId: "org-1" },
    });
    expect(await organizations.revokeInvitation("inv-1")).toMatchObject({
      ok: true,
      data: false,
    });
    expect(await organizations.delete("org-1")).toMatchObject({
      ok: true,
      data: true,
    });
    expect(seen).toEqual([
      "organization.updated",
      "organization.role_changed",
      "organization.ownership_transferred",
      "organization.switched",
      "organization.member_added",
      "organization.deleted",
    ]);
  });

  it("removes members, leaves, marks use and declines invitations", async () => {
    const { transport, calls } = fake({
      remove_member: true,
      leave_organization: true,
      mark_used: true,
      decline_invitation: true,
      invitation_preview: null,
    });
    const events = new EventHub();
    const seen: string[] = [];
    events.on("block", (event) => seen.push(event.type));
    const organizations = createOrganizations({
      transport,
      events,
      actorId: "user-1",
    });
    expect(await organizations.removeMember("org-1", "user-2")).toMatchObject({
      ok: true,
      data: true,
    });
    expect(await organizations.leave("org-1")).toMatchObject({
      ok: true,
      data: true,
    });
    expect(await organizations.markUsed("org-1")).toMatchObject({
      ok: true,
      data: true,
    });
    expect(await organizations.declineInvitation("token")).toMatchObject({
      ok: true,
      data: true,
    });
    expect(await organizations.previewInvitation("token")).toMatchObject({
      ok: true,
      data: undefined,
    });
    expect(seen).toEqual([
      "organization.member_removed",
      "organization.member_left",
    ]);
    expect(calls.map((call) => call.fn)).toEqual([
      "remove_member",
      "leave_organization",
      "mark_used",
      "decline_invitation",
      "invitation_preview",
    ]);
  });

  it("reads slug problems and previews", async () => {
    const { transport } = fake({
      organization_slug_problem: "taken",
      invitation_preview: {
        status: "pending",
        email: "ada@example.com",
        role: "member",
        tenant: null,
        expires_at: "2026-10-10T12:00:00Z",
        organization: null,
        prefill: null,
        roleLabel: "Team member",
        branding: { color: "#123456" },
      },
    });
    const organizations = createOrganizations({ transport });
    expect(await organizations.slugProblem("acme")).toMatchObject({
      ok: true,
      data: "taken",
    });
    const preview = await organizations.previewInvitation("token");
    expect(preview).toMatchObject({
      ok: true,
      data: { status: "pending", organizationId: null, prefill: {} },
    });
    expect(preview.data?.extra).toEqual({
      roleLabel: "Team member",
      branding: { color: "#123456" },
    });
    const empty = createOrganizations({ transport: fake({}).transport });
    expect(await empty.slugProblem("free")).toMatchObject({
      ok: true,
      data: undefined,
    });
    expect(await empty.previewInvitation("nope")).toMatchObject({
      ok: true,
      data: undefined,
    });
  });

  it("rejects malformed function results", async () => {
    const { transport } = fake({
      organization_slug_problem: "odd",
      invitation_preview: { status: "lost" },
      switch_organization: "org-1",
    });
    const organizations = createOrganizations({ transport });
    for (const result of [
      await organizations.slugProblem("x"),
      await organizations.previewInvitation("x"),
      await organizations.switch("org-1"),
    ]) {
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "unexpected" },
      });
    }
  });
});

describe("sqlTransport", () => {
  it("calls the function with named arguments", async () => {
    const queryRaw = vi.fn(() => Promise.resolve([{ value: "org-1" }]));
    const transport = sqlTransport({
      queryRaw,
      query: vi.fn(),
    } as unknown as Parameters<typeof sqlTransport>[0]);
    expect(
      await transport.call("better_supabase", "create_organization", {
        attrs: { name: "Acme" },
        skipped: undefined,
        flag: null,
      }),
    ).toBe("org-1");
    expect(queryRaw).toHaveBeenCalledWith(
      'select "better_supabase"."create_organization"("attrs" => $1, "flag" => $2) as value',
      ['{"name":"Acme"}', null],
    );
  });

  it("returns null without a row", async () => {
    const transport = sqlTransport({
      queryRaw: () => Promise.resolve([]),
    });
    expect(await transport.call("s", "f", {})).toBeNull();
  });
});

describe("rpcTransport", () => {
  it("calls rpc on the module schema without undefined arguments", async () => {
    const rpc = vi.fn(() => Promise.resolve({ data: true, error: null }));
    const schema = vi.fn(() => ({ rpc }));
    const transport = rpcTransport({ schema });
    expect(
      await transport.call("block", "mark_used", {
        organization: "o",
        x: undefined,
      }),
    ).toBe(true);
    expect(schema).toHaveBeenCalledWith("block");
    expect(rpc).toHaveBeenCalledWith("mark_used", { organization: "o" });
  });

  it("sends every call to the API schema when one is given", async () => {
    const rpc = vi.fn(() => Promise.resolve({ data: 1, error: null }));
    const schema = vi.fn(() => ({ rpc }));
    const transport = rpcTransport({ schema }, { schema: "api" });
    await transport.call("better_supabase", "mark_used", {});
    expect(schema).toHaveBeenCalledWith("api");
  });

  it("throws the PostgREST error as an Error with its fields", async () => {
    const transport = rpcTransport({
      schema: () => ({
        rpc: () =>
          Promise.resolve({
            data: null,
            error: {
              message: "nope",
              code: "42501",
              hint: "ORGANIZATION_FORBIDDEN",
            },
          }),
      }),
    });
    const organizations = createOrganizations({ transport });
    expect(await organizations.leave("organization")).toMatchObject({
      ok: false,
      error: {
        kind: "forbidden",
        message: "nope",
        hint: "ORGANIZATION_FORBIDDEN",
      },
    });
  });
});

describe("invitations by id", () => {
  it("lists the caller's invitations and answers them by id", async () => {
    const { transport, calls } = fake({
      my_invitations: [invitationRow, "not a row"],
      accept_invitation_by_id: "org-1",
      decline_invitation_by_id: true,
    });
    const organizations = createOrganizations({ transport });
    const mine = await organizations.myInvitations().orThrow();
    expect(mine).toHaveLength(1);
    expect(mine[0]).toMatchObject({ id: "inv-1", organizationId: "org-1" });
    expect(await organizations.acceptInvitationById("inv-1").orThrow()).toEqual(
      { organizationId: "org-1" },
    );
    expect(await organizations.declineInvitationById("inv-2").orThrow()).toBe(
      true,
    );
    expect(calls.map((call) => [call.fn, call.args])).toEqual([
      ["my_invitations", {}],
      ["accept_invitation_by_id", { invitation_id: "inv-1" }],
      ["decline_invitation_by_id", { invitation_id: "inv-2" }],
    ]);
  });
});
