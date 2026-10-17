import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/blocks/identities/index.ts";

import {
  beginLink,
  createIdentities,
  identityResolver,
  redeemLink,
} from "../../../src/blocks/identities/index.ts";

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

const slack = {
  kind: "chat",
  provider: "slack",
  value: "U1",
  workspace: "T1",
} as const;

describe("identityResolver", () => {
  it("resolves a linked user and a linked contact", async () => {
    const { call, transport: t } = transport((_fn, args) =>
      args["value"] === "U1"
        ? { kind: "user", userId: "user-1" }
        : { kind: "contact", contactId: "contact-1" },
    );
    const resolve = identityResolver(t);
    expect(await resolve(slack)).toEqual({ kind: "user", userId: "user-1" });
    expect(await resolve({ kind: "email", value: "a@example.test" })).toEqual({
      kind: "contact",
      contactId: "contact-1",
    });
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "principal_by_identity",
      {
        kind: "chat",
        provider: "slack",
        value: "U1",
        workspace: "T1",
      },
    );
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "principal_by_identity",
      {
        kind: "email",
        provider: null,
        value: "a@example.test",
        workspace: null,
      },
    );
  });

  it("returns null for an unlinked identity or a malformed row", async () => {
    for (const row of [
      null,
      "user-1",
      { kind: "user" },
      { kind: "contact", contactId: 7 },
      { kind: "service", userId: "x" },
    ]) {
      const resolve = identityResolver(transport(() => row).transport, {
        schema: "app_private",
      });
      expect(await resolve(slack)).toBeNull();
    }
  });

  it("rejects on a database error instead of answering anonymous", async () => {
    const resolve = identityResolver(
      transport(() => {
        throw Object.assign(new Error("permission denied"), { code: "42501" });
      }).transport,
    );
    await expect(resolve(slack)).rejects.toMatchObject({
      error: { kind: "forbidden" },
    });
  });
});

describe("link flow", () => {
  it("begins a link and redeems the code", async () => {
    const { call, transport: t } = transport((fn) =>
      fn === "begin_identity_link"
        ? { code: "ABC123DEF456", expires_at: AT }
        : { id: "link-1", user_id: "user-1" },
    );
    const code = await beginLink(t, "chat", "slack").orThrow();
    expect(code.code).toBe("ABC123DEF456");
    expect(code.expiresAt.toString()).toBe("2026-10-14T07:00:00Z");
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "begin_identity_link",
      { kind: "chat", provider: "slack" },
    );
    expect(await redeemLink(t, code.code, slack).orThrow()).toEqual({
      id: "link-1",
      userId: "user-1",
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "redeem_identity_link",
      { code: "ABC123DEF456", ...slack },
    );
    await createIdentities({ transport: t }).beginLink("email").orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "begin_identity_link",
      { kind: "email", provider: null },
    );
  });

  it("maps a refused code to a DbError with its hint", async () => {
    const refused = await redeemLink(
      transport(() => {
        throw Object.assign(new Error("invalid or expired link code"), {
          code: "22023",
          hint: "IDENTITY_LINK_INVALID",
        });
      }).transport,
      "nope",
      slack,
    );
    expect(refused).toMatchObject({
      ok: false,
      error: { hint: "IDENTITY_LINK_INVALID" },
    });
  });
});

describe("createIdentities", () => {
  it("lists, unlinks and backfills", async () => {
    const { transport: t } = transport((fn) => {
      switch (fn) {
        case "my_identities": {
          return [
            {
              id: "link-1",
              kind: "email",
              provider: null,
              value: "a@example.test",
              workspace: null,
              source: "verified_email",
              created_at: AT,
            },
          ];
        }
        case "unlink_identity": {
          return true;
        }
        case "backfill_verified_emails": {
          return "3";
        }
        default: {
          return null;
        }
      }
    });
    const identities = createIdentities({ transport: t });
    expect(await identities.list().orThrow()).toMatchObject([
      {
        id: "link-1",
        kind: "email",
        provider: null,
        workspace: null,
        source: "verified_email",
      },
    ]);
    expect(await identities.unlink("link-1").orThrow()).toBe(true);
    expect(await identities.backfillVerifiedEmails().orThrow()).toBe(3);
  });

  it("refuses a row with an unknown kind", async () => {
    const identities = createIdentities({
      transport: transport(() => [
        { id: "x", kind: "fax", value: "1", source: "link", created_at: AT },
      ]).transport,
    });
    expect(await identities.list()).toMatchObject({ ok: false });
  });
});
