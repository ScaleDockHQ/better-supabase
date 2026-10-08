import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { actorOf } from "../../src/auth/actor.ts";
import { actClaim, impersonatorOf } from "../../src/auth/impersonation.ts";
import { supportClaims } from "../../src/auth/support.ts";
import { toSession } from "../../src/auth/view.ts";
import { supabaseClaimFixtures } from "../../src/testing/index.ts";

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
      if (session.kind !== "user") throw new Error("expected a user session");
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
      actClaim({
        actor: impersonation.expect.actor.id,
        reason: "ticket 42",
      }),
    ).toEqual(impersonation.claims["act"]);
  });
});
