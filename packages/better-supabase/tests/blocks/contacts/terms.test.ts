import { describe, expect, it } from "vitest";

import {
  deliveryPreferenceOf,
  paymentTermOf,
} from "../../../src/blocks/contacts/terms.ts";

const TERM = {
  id: "t1",
  organizationId: "o",
  code: "2-10-NET30",
  name: "2 percent in 10 days",
  days: 30,
  discountBps: 200,
  discountDays: 10,
  creditRestrictionBps: 0,
};

describe("paymentTermOf", () => {
  it("reads the terms", () => {
    expect(paymentTermOf(TERM)).toEqual(TERM);
  });

  it("rejects a count that isn't an integer", () => {
    expect(() => paymentTermOf({ ...TERM, days: "30" })).toThrow(
      "payment terms days is not an integer",
    );
    expect(() => paymentTermOf({ ...TERM, discountBps: 1.5 })).toThrow(
      "payment terms discount is not an integer",
    );
  });

  it("rejects a value that isn't a record", () => {
    expect(() => paymentTermOf(null)).toThrow("payment terms");
  });
});

describe("deliveryPreferenceOf", () => {
  const PREFERENCE = {
    id: "d1",
    organizationId: "o",
    partyId: "p",
    documentType: "invoice",
    channel: "email",
    copies: 1,
    email: "ap@example.test",
  };

  it("keeps the email when there is one", () => {
    expect(deliveryPreferenceOf(PREFERENCE)).toEqual(PREFERENCE);
  });

  it("leaves the email out when it is null", () => {
    expect(
      deliveryPreferenceOf({ ...PREFERENCE, email: null }),
    ).not.toHaveProperty("email");
  });

  it("rejects an unknown channel", () => {
    expect(() =>
      deliveryPreferenceOf({ ...PREFERENCE, channel: "fax" }),
    ).toThrow("unknown delivery channel fax");
  });
});
