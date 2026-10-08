import type { SessionActor, SessionDelegation } from "../auth/actor.ts";
import type { Impersonator } from "../auth/impersonation.ts";

/**
 * Claims of a Supabase access token where someone acts for the user, with
 * what `toSession` reads from them: `actor`, `impersonator` and
 * `delegation`. Plain data, so another library that reads the same `act`
 * claim (RFC 8693) can test against the same fixtures.
 */
export interface SupabaseClaimFixture {
  /** Without `iat` and `exp`, so a test signer sets them. */
  readonly claims: { readonly sub: string; readonly [claim: string]: unknown };
  readonly expect: {
    readonly actor: SessionActor;
    /** Set for support and impersonated sessions only. */
    readonly impersonator?: Impersonator;
    /** Set for an `oauth-client` actor only. */
    readonly delegation?: SessionDelegation;
  };
}

export type SupabaseClaimFixtureName =
  | "supportSession"
  | "supportSessionReadOnly"
  | "impersonation"
  | "oauthClient"
  | "agentChain";

const base = {
  sub: "6f1c2c1e-5d0a-4d9e-9a51-6b1f0e7c2a10",
  aud: "authenticated",
  role: "authenticated",
  iss: "https://project.supabase.co/auth/v1",
  aal: "aal1",
  session_id: "b7a8f9c0-1111-4222-8333-944455556666",
  is_anonymous: false,
} as const;

const admin = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d";
const supportSessionId = "4e5f6a7b-8c9d-4e0f-9a1b-2c3d4e5f6a7b";
const client = "5f0e4d3c-2b1a-4098-8776-655443322110";
const chain = { sub: "agent-runner", act: { sub: "mcp-client-42" } } as const;

/**
 * `supportSession` and `supportSessionReadOnly` are what `supportClaims`
 * mints (`act.kind: "support"`), `impersonation` what `actingAs` mints
 * (`act.kind: "impersonation"`), `oauthClient` a Supabase OAuth server token
 * and `agentChain` an RFC 8693 chain without `kind`.
 */
export const supabaseClaimFixtures: Readonly<
  Record<SupabaseClaimFixtureName, SupabaseClaimFixture>
> = {
  supportSession: {
    claims: {
      ...base,
      act: {
        kind: "support",
        sub: admin,
        reason: "ticket 42",
        session_id: supportSessionId,
        read_only: false,
      },
    },
    expect: {
      actor: {
        kind: "support",
        id: admin,
        sessionId: supportSessionId,
        readOnly: false,
        reason: "ticket 42",
      },
      impersonator: {
        kind: "support",
        id: admin,
        sessionId: supportSessionId,
        readOnly: false,
        reason: "ticket 42",
      },
    },
  },
  supportSessionReadOnly: {
    claims: {
      ...base,
      act: {
        kind: "support",
        sub: admin,
        reason: "ticket 42",
        session_id: supportSessionId,
        read_only: true,
      },
    },
    expect: {
      actor: {
        kind: "support",
        id: admin,
        sessionId: supportSessionId,
        readOnly: true,
        reason: "ticket 42",
      },
      impersonator: {
        kind: "support",
        id: admin,
        sessionId: supportSessionId,
        readOnly: true,
        reason: "ticket 42",
      },
    },
  },
  impersonation: {
    claims: {
      ...base,
      act: { kind: "impersonation", sub: admin, reason: "ticket 42" },
    },
    expect: {
      actor: { kind: "impersonation", id: admin, reason: "ticket 42" },
      impersonator: { kind: "impersonation", id: admin, reason: "ticket 42" },
    },
  },
  oauthClient: {
    claims: {
      ...base,
      client_id: client,
      scope: "openid email posts:read",
    },
    expect: {
      actor: { kind: "oauth-client", id: client },
      delegation: { scopes: ["openid", "email", "posts:read"] },
    },
  },
  agentChain: {
    claims: { ...base, scope: "posts:read", act: chain },
    expect: {
      actor: { kind: "oauth-client", id: "agent-runner", chain },
      delegation: { scopes: ["posts:read"], chain },
    },
  },
};
