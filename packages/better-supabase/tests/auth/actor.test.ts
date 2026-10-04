import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { actorOf, delegationOf } from "../../src/auth/actor.ts";
import { resolveAuth } from "../../src/auth/resolve.ts";
import { toSession } from "../../src/auth/view.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";

// Copies of PermDock's `oauthClient` and `actChain` Supabase claim fixtures.
const base = {
  sub: "6f1c2c1e-5d0a-4d9e-9a51-6b1f0e7c2a10",
  aud: "authenticated",
  role: "authenticated",
  iss: "https://project.supabase.co/auth/v1",
  aal: "aal1",
  session_id: "b7a8f9c0-1111-4222-8333-944455556666",
  is_anonymous: false,
};
const oauthClient = {
  ...base,
  client_id: "5f0e4d3c-2b1a-4098-8776-655443322110",
  scope: "openid email posts:read",
  user_role: "member",
};
const actChain = {
  ...base,
  scope: "posts:read",
  act: { sub: "agent-runner", act: { sub: "mcp-client-42" } },
};

function user(claims: Record<string, unknown>): AuthState {
  return {
    kind: "user",
    source: "bearer",
    token: "token",
    user: { id: base.sub, role: "authenticated" },
    claims,
    expiresAt: null,
  } as unknown as AuthState;
}

describe("actorOf and delegationOf", () => {
  it("reads an OAuth client from client_id", () => {
    expect(actorOf(oauthClient)).toEqual({
      ok: true,
      actor: { id: oauthClient.client_id, kind: "oauth-client" },
    });
    expect(delegationOf(oauthClient)).toEqual({
      scopes: ["openid", "email", "posts:read"],
    });
  });

  it("takes the outermost sub of an act chain as the current actor", () => {
    expect(actorOf(actChain)).toEqual({
      ok: true,
      actor: { id: "agent-runner", kind: "oauth-client", chain: actChain.act },
    });
  });

  it("rejects a chain level without a sub", () => {
    for (const act of [
      "agent",
      { sub: "" },
      { sub: "a", act: { act: { sub: "b" } } },
      [{ sub: "a" }],
    ]) {
      expect(actorOf({ ...base, act })).toEqual({
        ok: false,
        reason: "invalid-chain",
      });
    }
  });

  it("reads support and impersonation levels by act.kind", () => {
    const admin = "admin-1";
    expect(
      actorOf({
        ...base,
        act: { kind: "support", sub: admin, session_id: "s1" },
      }),
    ).toEqual({
      ok: true,
      actor: { kind: "support", id: admin, sessionId: "s1", readOnly: true },
    });
    // 0.5.0 minted support tokens without kind; session_id marks them until 0.6.
    expect(
      actorOf({
        ...base,
        act: { sub: admin, session_id: "s1", read_only: false, reason: "r" },
      }),
    ).toEqual({
      ok: true,
      actor: {
        kind: "support",
        id: admin,
        sessionId: "s1",
        readOnly: false,
        reason: "r",
      },
    });
    expect(
      actorOf({ ...base, act: { kind: "impersonation", sub: admin } }),
    ).toEqual({ ok: true, actor: { kind: "impersonation", id: admin } });
  });

  it("fails closed on an unknown kind or a malformed support level", () => {
    for (const act of [
      { kind: "auditor", sub: "a" },
      { kind: 1, sub: "a" },
      { kind: "oauth-client", sub: "a" },
      { kind: "support", sub: "a" },
      { kind: "support", sub: "a", session_id: "" },
      { sub: "a", session_id: 7 },
      { kind: "support", sub: "a", session_id: "s1", read_only: "yes" },
    ]) {
      expect(actorOf({ ...base, act })).toEqual({
        ok: false,
        reason: "invalid-chain",
      });
    }
  });

  it("sets delegation only for an oauth-client actor", () => {
    const support = toSession(
      user({
        ...base,
        scope: "posts:read",
        act: { kind: "support", sub: "admin-1", session_id: "s1" },
      }),
    );
    expect(support).toMatchObject({ actor: { kind: "support" } });
    expect(support).not.toHaveProperty("delegation");
  });

  it("reads scope lists and ignores empty scopes", () => {
    expect(delegationOf({ scope: ["a", 1, "b"] })).toEqual({
      scopes: ["a", "b"],
    });
    expect(delegationOf({ scope: "  " })).toBeUndefined();
    expect(actorOf(base)).toEqual({ ok: true });
  });
});

describe("session.actor and session.delegation", () => {
  it("follow the PermDock fixtures", () => {
    expect(toSession(user(oauthClient))).toMatchObject({
      actor: { id: oauthClient.client_id, kind: "oauth-client" },
      delegation: { scopes: ["openid", "email", "posts:read"] },
    });
    expect(toSession(user(actChain))).toMatchObject({
      actor: { id: "agent-runner", kind: "oauth-client" },
      delegation: { scopes: ["posts:read"], chain: actChain.act },
    });
  });

  it("leaves both out for the user's own session", () => {
    const session = toSession(user({ ...base, scope: "openid" }));
    expect(session).not.toHaveProperty("actor");
    expect(session).not.toHaveProperty("delegation");
  });

  it("resolves a malformed chain to invalid, never to the user", async () => {
    const signer = await createTestSigner();
    const token = await signer.sign({ sub: base.sub, act: { sub: 7 } });
    const { auth } = await resolveAuth(
      new Request("https://app.test", {
        headers: { authorization: `Bearer ${token}` },
      }),
      {
        env: {
          url: "https://abcdefghijklmnopqrst.supabase.co",
          publishableKey: "sb_publishable_test",
          jwksUrl: new URL(
            "https://abcdefghijklmnopqrst.supabase.co/auth/v1/.well-known/jwks.json",
          ),
        },
        jwks: signer.jwks as never,
      },
    );
    expect(auth).toMatchObject({
      kind: "invalid",
      reason: "actor",
      error: { kind: "unauthorized", code: "ACTOR_INVALID" },
    });
  });
});
