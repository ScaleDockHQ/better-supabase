import { describe, expect, it } from "vitest";

import { createGuests, guestsBlock } from "../../../src/blocks/guests/index.ts";
import { guestsBinding } from "../../../src/blocks/guests/record-binding.ts";
import {
  guestGrantSchema,
  guestInviteSchema,
  guestSectionGrantSchema,
} from "../../../src/blocks/guests/schemas.ts";

const AT = "2026-10-22T10:00:00Z";
const LATER = "2026-11-22T10:00:00Z";

const GUEST = {
  id: "g1",
  organizationId: "org-1",
  email: "jane@client.example",
  name: "Jane",
  userId: "u2",
  partyType: "customer",
  partyId: "c1",
  status: "active",
  invitedBy: "u1",
  expiresAt: LATER,
  acceptedAt: AT,
  revokedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const BARE_GUEST = {
  id: "g2",
  organizationId: "org-1",
  email: "sam@contractor.example",
  name: null,
  userId: null,
  partyType: null,
  partyId: null,
  status: "invited",
  invitedBy: null,
  expiresAt: null,
  acceptedAt: null,
  revokedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const GRANT = {
  id: "r1",
  organizationId: "org-1",
  guestId: "g1",
  subjectType: "invoice",
  subjectId: "i1",
  actions: ["read", "comment"],
  grantedBy: "u1",
  expiresAt: LATER,
  createdAt: AT,
  updatedAt: AT,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createGuests", () => {
  it("invites with a party and returns the one-time token", async () => {
    const fake = fakeTransport({
      invite_guest: {
        ...BARE_GUEST,
        partyType: "customer",
        partyId: "c1",
        token: "t0k",
      },
    });

    const guests = createGuests({ transport: fake.transport, tenant: "org-1" });

    const invite = await guests
      .invite({
        email: "sam@contractor.example",
        name: "Sam",
        party: { type: "customer", id: "c1" },
        expiresAt: Temporal.Instant.from(LATER),
      })
      .orThrow();

    expect(invite).toMatchObject({
      id: "g2",
      status: "invited",
      party: { type: "customer", id: "c1" },
      token: "t0k",
    });
    expect(invite.name).toBeUndefined();
    expect(invite.userId).toBeUndefined();
    expect(fake.calls).toEqual([
      [
        "invite_guest",
        {
          tenant: "org-1",
          email: "sam@contractor.example",
          name: "Sam",
          party_type: "customer",
          party_id: "c1",
          expires_at: LATER,
        },
      ],
    ]);
  });

  it("leaves the token out when the guest already accepted", async () => {
    const fake = fakeTransport({ invite_guest: { ...GUEST, token: null } });
    const guests = createGuests({ transport: fake.transport, tenant: "org-1" });

    const invite = await guests
      .invite({ email: "jane@client.example" })
      .orThrow();

    expect(invite.token).toBeUndefined();
    expect(invite.acceptedAt?.toString()).toBe(AT);
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      email: "jane@client.example",
      name: null,
      party_type: null,
      party_id: null,
      expires_at: undefined,
    });
  });

  it("fails without a tenant for tenant-scoped calls", async () => {
    const fake = fakeTransport({});
    const guests = createGuests({ transport: fake.transport });

    expect(await guests.list()).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(await guests.invite({ email: "a@b.example" })).toMatchObject({
      ok: false,
      error: { hint: "TENANT_REQUIRED" },
    });
    expect(fake.calls).toEqual([]);
  });

  it("accepts and revokes without a tenant", async () => {
    const fake = fakeTransport({
      accept_guest_invite: GUEST,
      revoke_guest: { ...GUEST, status: "revoked", revokedAt: AT },
    });

    const guests = createGuests({ transport: fake.transport });

    const accepted = await guests.accept("t0k").orThrow();
    const revoked = await guests.revoke("g1").orThrow();

    expect(accepted).toMatchObject({
      id: "g1",
      userId: "u2",
      party: { type: "customer", id: "c1" },
      invitedBy: "u1",
    });
    expect(revoked.status).toBe("revoked");
    expect(revoked.revokedAt?.toString()).toBe(AT);
    expect(fake.calls).toEqual([
      ["accept_guest_invite", { token: "t0k" }],
      ["revoke_guest", { guest_id: "g1" }],
    ]);
  });

  it("lists guests with and without filters", async () => {
    const fake = fakeTransport({ list_guests: [GUEST, BARE_GUEST] });
    const guests = createGuests({ transport: fake.transport, tenant: "org-1" });

    const all = await guests.list().orThrow();
    await guests
      .list({
        status: "active",
        before: Temporal.Instant.from(AT),
        pageSize: 10,
      })
      .orThrow();

    expect(all.map((guest) => guest.id)).toEqual(["g1", "g2"]);
    expect(all[1]?.party).toBeUndefined();
    expect(fake.calls).toEqual([
      [
        "list_guests",
        { tenant: "org-1", status: null, before: undefined, page_size: null },
      ],
      [
        "list_guests",
        { tenant: "org-1", status: "active", before: AT, page_size: 10 },
      ],
    ]);
  });

  it("refuses an unknown status from the database", async () => {
    const fake = fakeTransport({
      revoke_guest: { ...GUEST, status: "paused" },
    });

    const guests = createGuests({ transport: fake.transport });

    expect((await guests.revoke("g1")).ok).toBe(false);
  });

  it("grants with read by default and with actions and an expiry", async () => {
    const fake = fakeTransport({
      grant_guest_access: GRANT,
      revoke_guest_access: true,
    });

    const guests = createGuests({ transport: fake.transport });
    const invoice = { type: "invoice", id: "i1" };

    const grant = await guests
      .grant({ guestId: "g1", subject: invoice })
      .orThrow();

    await guests
      .grant({
        guestId: "g1",
        subject: invoice,
        input: {
          actions: ["comment", "upload"],
          expiresAt: Temporal.Instant.from(LATER),
        },
      })
      .orThrow();
    const removed = await guests.revokeGrant("r1").orThrow();

    expect(grant).toMatchObject({
      id: "r1",
      guestId: "g1",
      subject: invoice,
      actions: ["read", "comment"],
      grantedBy: "u1",
    });
    expect(grant.expiresAt?.toString()).toBe(LATER);
    expect(removed).toBe(true);
    expect(fake.calls).toEqual([
      [
        "grant_guest_access",
        {
          guest_id: "g1",
          subject_type: "invoice",
          subject_id: "i1",
          actions: ["read"],
          expires_at: undefined,
        },
      ],
      [
        "grant_guest_access",
        {
          guest_id: "g1",
          subject_type: "invoice",
          subject_id: "i1",
          actions: ["comment", "upload"],
          expires_at: LATER,
        },
      ],
      ["revoke_guest_access", { grant_id: "r1" }],
    ]);
  });

  it("refuses an unknown action from the database", async () => {
    const fake = fakeTransport({
      grant_guest_access: { ...GRANT, actions: ["delete"] },
    });

    const guests = createGuests({ transport: fake.transport });

    expect(
      (
        await guests.grant({
          guestId: "g1",
          subject: { type: "invoice", id: "i1" },
        })
      ).ok,
    ).toBe(false);
  });

  it("reads a record's guests, the caller's access and guest_can", async () => {
    const fake = fakeTransport({
      list_guest_grants: [
        { ...GRANT, grantedBy: null, expiresAt: null, guest: GUEST },
      ],
      my_guest_access: [{ ...GUEST, grants: [GRANT] }],
      guest_can: true,
    });

    const guests = createGuests({ transport: fake.transport });
    const invoice = { type: "invoice", id: "i1" };

    const grants = await guests.grants(invoice).orThrow();
    const mine = await guests.mine().orThrow();
    const canRead = await guests.can({ subject: invoice }).orThrow();
    await guests.can({ subject: invoice, action: "upload" }).orThrow();

    expect(grants[0]?.guest.email).toBe("jane@client.example");
    expect(grants[0]?.grantedBy).toBeUndefined();
    expect(grants[0]?.expiresAt).toBeUndefined();
    expect(mine[0]?.grants.map((grant) => grant.id)).toEqual(["r1"]);
    expect(canRead).toBe(true);
    expect(fake.calls).toEqual([
      ["list_guest_grants", { subject_type: "invoice", subject_id: "i1" }],
      ["my_guest_access", {}],
      [
        "guest_can",
        { subject_type: "invoice", subject_id: "i1", action: "read" },
      ],
      [
        "guest_can",
        { subject_type: "invoice", subject_id: "i1", action: "upload" },
      ],
    ]);
  });

  it("runs hooks around a method", async () => {
    const fake = fakeTransport({ guest_can: false });
    const seen: string[] = [];

    const guests = createGuests({
      transport: fake.transport,
      logger: console,
      hooks: {
        can: {
          before: () => {
            seen.push("before");
          },
        },
      },
    });

    expect(
      await guests.can({ subject: { type: "invoice", id: "i1" } }).orThrow(),
    ).toBe(false);
    expect(seen).toEqual(["before"]);
  });
});

describe("guestsBinding", () => {
  it("loads a record's grants and runs its writes", async () => {
    const fake = fakeTransport({
      list_guest_grants: [{ ...GRANT, guest: GUEST }],
      grant_guest_access: GRANT,
      revoke_guest_access: true,
    });

    const guests = createGuests({ transport: fake.transport });
    const invoice = { type: "invoice", id: "i1" };

    const rows = await guestsBinding.load(guests, invoice, undefined).orThrow();
    await guestsBinding.writes.grant
      .run(guests, invoice, { guestId: "g1", actions: ["comment"] })
      .orThrow();
    await guestsBinding.writes.revoke
      .run(guests, invoice, { id: "r1" })
      .orThrow();

    expect(rows.map((row) => row.id)).toEqual(["r1"]);
    expect(guestsBinding.module).toBe("guests");
    expect(guestsBinding.events).toEqual(["guest_grant.*", "guest.revoked"]);
    expect(fake.calls.map(([fn]) => fn)).toEqual([
      "list_guest_grants",
      "grant_guest_access",
      "revoke_guest_access",
    ]);
    expect(fake.calls[1]?.[1]).toMatchObject({ actions: ["comment"] });
  });
});

describe("guest schemas", () => {
  it("accept valid input and refuse unknown actions", () => {
    expect(
      validate(guestInviteSchema, { email: "jane@client.example" }).issues,
    ).toBeUndefined();
    expect(
      validate(guestGrantSchema, { actions: ["read", "upload"] }).issues,
    ).toBeUndefined();
    expect(
      validate(guestGrantSchema, { actions: ["delete"] }).issues,
    ).toBeDefined();
    expect(
      validate(guestSectionGrantSchema, {
        guestId: "6f1c2a52-6d6c-4d55-9d4e-0f7c1b1a2b3c",
      }).issues,
    ).toBeUndefined();
    expect(validate(guestSectionGrantSchema, {}).issues).toBeDefined();
  });

  it("are the manifest's entity inputs", () => {
    expect(guestsBlock.name).toBe("guests");
    expect(guestsBlock.schemas["guest"]?.input).toBe(guestInviteSchema);
    expect(guestsBlock.schemas["guest_grant"]?.input).toBe(guestGrantSchema);
  });
});
