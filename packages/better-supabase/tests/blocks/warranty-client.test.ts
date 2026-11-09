import { describe, expect, it } from "vitest";

import { createWarranty } from "../../src/blocks/warranty/warranty.ts";

function transport(results: Record<string, unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });

      return Promise.resolve(results[fn]);
    },
  };
}

const claim = {
  id: "c1",
  organizationId: "org-1",
  title: "Broken seal",
  assetId: "a1",
  amount: "1000",
  currency: "EUR",
  status: "approved",
  supplierId: "s1",
  manufacturer: "Acme",
  decision: "wear",
  decidedAt: "2026-11-01T00:00:00Z",
  decidedBy: "u1",
};

describe("warranty client", () => {
  it("files, submits, decides and lists claims", async () => {
    const t = transport({
      create_warranty_claim: claim,
      submit_warranty_claim: { ...claim, status: "submitted" },
      decide_warranty_claim: claim,
      list_warranty_claims: [claim, { ...claim, id: "c2", status: "draft" }],
    });

    const warranty = createWarranty({ transport: t, tenant: "org-1" });

    const created = await warranty.createClaim({
      title: "Broken seal",
      assetId: "a1",
      amount: 1000n,
      currency: "EUR",
      supplierId: "s1",
      manufacturer: "Acme",
    });

    expect(created.ok ? created.data.status : created.error.hint).toBe(
      "approved",
    );
    expect(t.calls[0]).toMatchObject({
      fn: "create_warranty_claim",
      args: { tenant: "org-1" },
    });

    await warranty.submit("c1");
    await warranty.decide("c1", "approved", "wear");
    await warranty.decide("c1", "closed");

    const listed = await warranty.list({
      status: "approved",
      assetId: "a1",
      limit: 10,
      offset: 0,
    });

    expect(listed.ok ? listed.data : []).toHaveLength(2);
  });

  it("refuses a claim when the caller has no organization", async () => {
    const t = transport({});
    const warranty = createWarranty({ transport: t });

    const result = await warranty.createClaim({
      title: "Broken seal",
      assetId: "a1",
      amount: 1000n,
      currency: "EUR",
    });

    expect(result.ok ? undefined : result.error.hint).toBe("TENANT_REQUIRED");
  });
});
