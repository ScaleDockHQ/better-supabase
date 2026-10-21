import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { actorOf, agentClaims } from "../../src/auth/actor.ts";
import { actClaim, impersonatorOf } from "../../src/auth/impersonation.ts";
import { supportClaims } from "../../src/auth/support.ts";
import { toSession } from "../../src/auth/view.ts";
import {
  actCases,
  supabaseClaimFixtures,
  supabaseInvalidClaimFixtures,
} from "../../src/testing/index.ts";

function user(claims: Readonly<Record<string, unknown>>): AuthState {
  return {
    kind: "user",
    source: "bearer",
    token: "token",
    user: { id: String(claims["sub"]), role: "authenticated" },
    claims,
    expiresAt: null,
  } as unknown as AuthState;
}

describe("supabaseClaimFixtures", () => {
  for (const [name, fixture] of Object.entries(supabaseClaimFixtures)) {
    it(`${name}: reads as expected`, () => {
      expect(actorOf(fixture.claims)).toEqual({
        ok: true,
        actor: fixture.expect.actor,
      });
      expect(impersonatorOf(fixture.claims)).toEqual(
        fixture.expect.impersonator,
      );
      const session = toSession(user(fixture.claims));
      expect(session).toMatchObject({ actor: fixture.expect.actor });

      if (session.kind !== "user") {
        throw new Error("expected a user session");
      }

      expect(session.impersonator).toEqual(fixture.expect.impersonator);
      expect(session.delegation).toEqual(fixture.expect.delegation);
    });
  }

  it("matches what supportClaims and actClaim mint", () => {
    const { supportSession, supportSessionReadOnly, impersonation } =
      supabaseClaimFixtures;

    for (const fixture of [supportSession, supportSessionReadOnly]) {
      const act = fixture.claims["act"] as Record<string, unknown>;
      const { act: _act, ...target } = fixture.claims;
      expect(
        supportClaims(
          {
            id: String(act["session_id"]),
            adminId: String(act["sub"]),
            targetUserId: fixture.claims.sub,
            reason: String(act["reason"]),
            readOnly: act["read_only"] === true,
          },
          target,
        ),
      ).toEqual(fixture.claims);
    }

    expect(
      actClaim({ actor: impersonation.expect.actor.id, reason: "ticket 42" }),
    ).toEqual(impersonation.claims["act"]);
  });

  it("agentRunReadOnly is what agentClaims mints with readOnly", () => {
    const { agentRunReadOnly } = supabaseClaimFixtures;
    const { act, ...user } = agentRunReadOnly.claims;
    const agent = act as Record<string, unknown>;

    expect(
      agentClaims(
        { ...user, act: agent["act"] },
        { agent: "agent-7", tools: ["search_knowledge"], readOnly: true },
      ),
    ).toEqual(agentRunReadOnly.claims);
  });
});

/** The case in act-cases.json that covers each invalid fixture. */
const ACT_CASE_OF = {
  legacySupportSession: "session_id without kind (0.5.0 support)",
  supportReadOnlyNotBoolean: "support, read_only as a string",
  agentWithSessionId: "agent with session_id",
  agentEmptyToolName: "agent, empty tool name",
  agentToolsNotArray: "agent, tools not a list",
  agentReadOnlyNotBoolean: "agent, read_only as a string",
  unknownKind: "unknown kind",
  levelWithoutSub: "nested level without sub",
} as const satisfies Record<keyof typeof supabaseInvalidClaimFixtures, string>;

describe("supabaseInvalidClaimFixtures", () => {
  for (const [name, fixture] of Object.entries(supabaseInvalidClaimFixtures)) {
    it(`${name}: refuses the session`, () => {
      expect(actorOf(fixture.claims)).toEqual({
        ok: false,
        reason: "invalid-chain",
      });

      const session = toSession(user(fixture.claims));
      expect(session).toMatchObject({
        kind: fixture.expect.kind,
        reason: fixture.expect.reason,
        error: { code: fixture.expect.code },
      });
    });

    it(`${name}: act-cases.json refuses the same chain`, () => {
      const caseName = ACT_CASE_OF[name as keyof typeof ACT_CASE_OF];
      const actCase = actCases.cases.find((entry) => entry.name === caseName);

      expect(actCase).toMatchObject({ valid: false, kind: null });
    });
  }
});
