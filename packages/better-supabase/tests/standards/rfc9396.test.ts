import { describe, expect, it } from "vitest";

import { contextClaims, delegatedClaims } from "../../src/auth/delegation.ts";
import { unwrap, withContext } from "../../src/blocks/jobs/envelope.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const actor = { id: "user-1", kind: "user" as const };

/** RFC 9396 section 2, the payment initiation example. */
const DETAILS = [
  {
    type: "payment_initiation",
    actions: ["initiate", "status", "cancel"],
    locations: ["https://example.com/payments"],
    instructedAmount: { currency: "EUR", amount: "123.50" },
    creditorName: "Merchant A",
  },
];

describe(`RFC 9396 authorization details (${SPEC_PINS.rfc9396})`, () => {
  it("keeps every entry and its type-specific fields", () => {
    expect(
      delegatedClaims({ client_id: "c", authorization_details: DETAILS }),
    ).toEqual({
      ok: true,
      delegation: { client_id: "c", authorization_details: DETAILS },
    });
  });

  it("requires a JSON array of objects with a type (section 2)", () => {
    for (const details of [
      DETAILS[0],
      [{ actions: ["read"] }],
      [{ type: "" }],
      ["payment_initiation"],
    ]) {
      expect(
        delegatedClaims({ client_id: "c", authorization_details: details }),
      ).toEqual({ ok: false, reason: "invalid-delegation" });
    }
  });

  it("survives a job envelope and comes back in the run claims", () => {
    const stored = withContext(null, {
      actor,
      claims: { client_id: "c", authorization_details: DETAILS },
    });
    const { context } = unwrap(JSON.parse(JSON.stringify(stored)));
    expect(contextClaims(context)).toMatchObject({
      ok: true,
      claims: { authorization_details: DETAILS },
    });
  });
});
