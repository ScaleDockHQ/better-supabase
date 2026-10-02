import { createClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import { customerDetail, customerDetailSet } from "./customer-detail.ts";
import { type Json } from "./generated.ts";
import { sb } from "./latency.ts";

const ORG = "00000000-0000-4000-8000-0000000000aa";
const PROJECT_URL = "https://crm.supabase.co";

function connect(answer: (url: URL) => Json) {
  const fetch = vi.fn<typeof globalThis.fetch>((input) =>
    Promise.resolve(Response.json(answer(new URL(String(input))))),
  );
  const db = sb.connect(
    createClient(PROJECT_URL, "sb_publishable_test", { global: { fetch } }),
  );
  const urls = () => fetch.mock.calls.map(([input]) => new URL(String(input)));
  return { db, urls };
}

describe("customer detail", () => {
  it("reads the customer, contacts with methods, locations and counts in one call", async () => {
    const { db, urls } = connect(() => ({
      id: 7,
      companyName: "Acme",
      isBusiness: true,
      status: "active",
      billingEmail: null,
      website: null,
      customerContacts: [
        {
          id: 1,
          jobTitle: "Owner",
          isPrimary: true,
          contactProfile: {
            id: "p1",
            firstName: "Ada",
            lastName: "Lovelace",
            displayName: null,
            contactMethods: [
              {
                id: "m1",
                type: "email",
                value: "ada@acme.test",
                isPrimary: true,
              },
            ],
          },
        },
      ],
      customerLocationsByCustomer: [],
      _count_quotes: [{ count: 3 }],
      _count_invoices: [{ count: 2 }],
    }));

    const customer = await customerDetail(db, ORG, 7).orThrow();

    expect(db.$stats()).toMatchObject({ calls: 1, waves: 1 });
    expect(
      customer?.customerContacts[0]?.contactProfile.contactMethods,
    ).toEqual([
      { id: "m1", type: "email", value: "ada@acme.test", isPrimary: true },
    ]);
    expect(customer).toMatchObject({ _count: { quotes: 3, invoices: 2 } });
    const [call] = urls();
    expect(call!.pathname).toBe("/rest/v1/customers");
    expect(call!.searchParams.get("id")).toBe("eq.7");
    expect(call!.searchParams.get("organization_id")).toBe(`eq.${ORG}`);
    const select = call!.searchParams.get("select") ?? "";
    expect(select).toContain(
      "contactMethods:contact_methods!contact_methods_contact_profile_id_fkey(",
    );
    expect(select).toContain(
      "_count_quotes:quotes!quotes_customer_id_fkey(count)",
    );
    expect(select).toContain(
      "_count_invoices:invoices!invoices_customer_id_fkey(count)",
    );
  });

  it("reads each section from one read set GET", async () => {
    const { db, urls } = connect(() => ({
      customer: { rows: [{ id: 7, companyName: "Acme" }], count: null },
      contacts: { rows: [], count: null },
      locations: { rows: [], count: null },
      quotes: { rows: [], count: 3 },
      invoices: { rows: [], count: 2 },
    }));

    const detail = await db
      .$many(customerDetailSet, { organizationId: ORG, customerId: 7 })
      .orThrow();

    expect(db.$stats()).toMatchObject({ calls: 1, waves: 1 });
    expect(detail).toMatchObject({
      customer: { id: 7, companyName: "Acme" },
      contacts: [],
      locations: [],
      quotes: 3,
      invoices: 2,
    });
    const [call] = urls();
    expect(call!.pathname).toBe("/rest/v1/rpc/rs_customer_detail");
    expect(JSON.parse(call!.searchParams.get("p")!)).toEqual({
      organizationId: ORG,
      customerId: 7,
    });
  });
});
