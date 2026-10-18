import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { actorOf, agentClaims, delegationOf } from "../../src/auth/actor.ts";
import { delegatedClaims } from "../../src/auth/delegation.ts";
import { impersonatorOf } from "../../src/auth/impersonation.ts";
import { resolveAuth } from "../../src/auth/resolve.ts";
import { toSession } from "../../src/auth/view.ts";
import { actCases } from "../../src/testing/act-cases.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";

// An OAuth client token and a token with a delegation chain in `act`.
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
    expect(delegationOf(oauthClient)).toEqual({ scopes: ["posts:read"] });
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
      { sub: "a", session_id: "s1", read_only: false },
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

  it("leaves out identity scopes but keeps the delegation", () => {
    expect(
      delegationOf({ scope: "openid profile phone address offline_access" }),
    ).toEqual({ scopes: [] });
    expect(delegationOf({ scope: ["email", "posts:write"] })).toEqual({
      scopes: ["posts:write"],
    });
  });

  it("keeps an agent on an identity-only token limited to its scopes", () => {
    const session = toSession(
      user({
        ...base,
        scope: "openid email",
        act: { kind: "agent", sub: "agent-7" },
      }),
    );

    expect(session).toMatchObject({
      actor: { kind: "agent" },
      delegation: { scopes: [] },
    });
  });

  it("makes toSession refuse a malformed chain on a hand-built state", () => {
    for (const act of [
      { kind: "agent", sub: "a", session_id: "s1" },
      { kind: "agent", sub: "a", tools: [""] },
      { kind: "agent", sub: "a", tools: "search" },
      { kind: "agent", sub: "a", read_only: "true" },
      { sub: "a", session_id: "s1" },
    ]) {
      expect(toSession(user({ ...base, act }))).toMatchObject({
        kind: "invalid",
        reason: "actor",
        error: { code: "ACTOR_INVALID" },
      });
    }
  });
});

describe("session.actor and session.delegation", () => {
  it("follow the claim fixtures", () => {
    expect(toSession(user(oauthClient))).toMatchObject({
      actor: { id: oauthClient.client_id, kind: "oauth-client" },
      delegation: { scopes: ["posts:read"] },
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

describe("agent actors", () => {
  const agentAct = { kind: "agent", sub: "agent-1", tools: ["lookup"] };

  it("reads an agent level with its tools and keeps the chain", () => {
    expect(actorOf({ ...base, act: agentAct })).toEqual({
      ok: true,
      actor: {
        kind: "agent",
        id: "agent-1",
        tools: ["lookup"],
        readOnly: false,
        chain: agentAct,
      },
    });
    expect(impersonatorOf({ ...base, act: agentAct })).toBeUndefined();
  });

  it("refuses tools that are not a list of names, and a session id", () => {
    for (const act of [
      { ...agentAct, tools: "lookup" },
      { ...agentAct, tools: [""] },
      { ...agentAct, session_id: "s1" },
    ]) {
      expect(actorOf({ ...base, act })).toEqual({
        ok: false,
        reason: "invalid-chain",
      });
    }
  });

  it("nests an earlier act under the agent and records the chain", () => {
    const claims = agentClaims(actChain, {
      agent: "agent-1",
      tools: ["lookup"],
    });

    expect(claims.act).toEqual({
      kind: "agent",
      sub: "agent-1",
      tools: ["lookup"],
      act: actChain.act,
    });
    expect(delegatedClaims(claims)).toEqual({
      ok: true,
      delegation: { scope: "posts:read", act: claims.act },
    });
  });

  it("writes tools and read_only only when they are set", () => {
    expect(agentClaims(base, { agent: "agent-1" }).act).toEqual({
      kind: "agent",
      sub: "agent-1",
    });
    expect(
      agentClaims(base, { agent: "agent-1", tools: [], readOnly: true }).act,
    ).toEqual({ kind: "agent", sub: "agent-1", tools: [], read_only: true });
  });
});

describe("act-cases.json", () => {
  it("is version 1 with unique case names", () => {
    expect(actCases.version).toBe(1);
    expect(new Set(actCases.cases.map((c) => c.name)).size).toBe(
      actCases.cases.length,
    );
  });

  it.each(actCases.cases)(
    "$name",
    ({ claims, valid, kind, readOnly, tools }) => {
      const outcome = actorOf(claims);

      expect(outcome.ok).toBe(valid);

      const actor = outcome.ok ? outcome.actor : undefined;

      expect(actor?.kind ?? null).toBe(kind);
      expect(
        actor !== undefined && "readOnly" in actor ? actor.readOnly : null,
      ).toBe(readOnly);
      expect(actor?.kind === "agent" ? (actor.tools ?? null) : null).toEqual(
        tools,
      );
    },
  );
});
