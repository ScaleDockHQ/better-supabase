import { describe, expect, it } from "vitest";

import { createReferrals } from "../../../src/blocks/referrals/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const CODE = {
  id: "rc1",
  organizationId: "org-1",
  code: "WELCOME1",
  referrerId: "u1",
  rewardAmount: "500",
  rewardUnit: "EUR",
  uses: 0,
  active: true,
  createdAt: "2026-01-01T00:00:00Z",
};

const REFERRAL = {
  id: "r1",
  organizationId: "org-1",
  codeId: "rc1",
  referrerId: "u1",
  referredUserId: "u2",
  status: "attributed",
  rewardAmount: "500",
  rewardUnit: "EUR",
  createdAt: "2026-01-02T00:00:00Z",
};

describe("createReferrals", () => {
  it("creates a code with a reward", async () => {
    const t = fieldsTransport({ create_referral_code: () => CODE });
    const referrals = createReferrals({ transport: t, tenant: "org-1" });

    const code = await referrals
      .createCode({ code: "WELCOME1", reward: { amount: 500n, unit: "EUR" } })
      .orThrow();

    expect(code.reward).toEqual({ amount: 500n, unit: "EUR" });
    expect(t.calls[0]).toEqual([
      "create_referral_code",
      {
        tenant: "org-1",
        code: "WELCOME1",
        reward_amount: "500",
        reward_unit: "EUR",
      },
    ]);
  });

  it("attributes a signup and qualifies it", async () => {
    const t = fieldsTransport({
      attribute_referral: () => REFERRAL,
      qualify_referral: () => ({
        ...REFERRAL,
        status: "rewarded",
        qualifiedAt: "2026-02-01T00:00:00Z",
        rewardedAt: "2026-02-01T00:00:00Z",
        ledgerTransactionId: "tx1",
      }),
    });

    const referrals = createReferrals({ transport: t, tenant: "org-1" });

    const attributed = await referrals
      .attribute({ code: "WELCOME1", referredUserId: "u2" })
      .orThrow();

    const rewarded = await referrals
      .qualify({ referredUserId: "u2", source: "invoices/inv-1" })
      .orThrow();

    expect(attributed.status).toBe("attributed");
    expect(rewarded?.status).toBe("rewarded");
    expect(rewarded?.ledgerTransactionId).toBe("tx1");
  });

  it("resolves undefined when nothing referred the user", async () => {
    const t = fieldsTransport({ qualify_referral: () => null });
    const referrals = createReferrals({ transport: t, tenant: "org-1" });

    await expect(
      referrals.qualify({ referredUserId: "u9" }).orThrow(),
    ).resolves.toBeUndefined();
  });

  it("voids a referral and lists by status", async () => {
    const t = fieldsTransport({
      void_referral: () => ({ ...REFERRAL, status: "void" }),
      list_referrals: () => [REFERRAL],
    });

    const referrals = createReferrals({ transport: t, tenant: "org-1" });

    const voided = await referrals
      .void({ referralId: "r1", reason: "fraud" })
      .orThrow();

    const listed = await referrals
      .listReferrals({ status: "attributed" })
      .orThrow();

    expect(voided.status).toBe("void");
    expect(listed).toHaveLength(1);
    expect(t.calls[1]).toEqual([
      "list_referrals",
      { tenant: "org-1", filters: { status: "attributed" } },
    ]);
  });

  it("reads a keyset page, its facets and its count of referrals", async () => {
    const t = fieldsTransport({
      list_referrals: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        if (filters["facet"] !== undefined) {
          return {
            facet: filters["facet"],
            values: [{ value: "attributed", count: { value: 2, exact: true } }],
          };
        }

        if (filters["count"] === true) {
          return { value: 7, exact: false };
        }

        return { items: [REFERRAL], hasMore: true, nextCursor: ["a", "b"] };
      },
    });

    const block = createReferrals({ transport: t, tenant: "org-1" });

    const page = await block
      .referralPage({
        limit: 1,
        sort: { by: "createdAt", direction: "asc" },
        filters: { status: ["attributed"] },
      })
      .orThrow();

    const facets = await block.referralFacets({ facets: ["status"] }).orThrow();
    const count = await block.referralCount().orThrow();

    expect(page.items).toHaveLength(1);
    expect(page).toMatchObject({ hasMore: true, nextCursor: ["a", "b"] });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org-1",
      filters: { limit: 1, sort: "createdAt", direction: "asc", paged: true },
    });
    expect(facets[0]?.facet).toBe("status");
    expect(facets[0]?.values[0]?.count).toEqual({ value: 2, exact: true });
    expect(count).toEqual({ value: 7, exact: false });
  });

  it("rejects a sort of referrals that is not declared", async () => {
    const t = fieldsTransport({});
    const block = createReferrals({ transport: t, tenant: "org-1" });

    const result = await block.referralPage({ sort: { by: "nope" } });

    expect(result.ok).toBe(false);
    expect(t.calls).toHaveLength(0);
  });

  it("reads a keyset page, its facets and its count of referral codes", async () => {
    const t = fieldsTransport({
      list_referral_codes: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        if (filters["facet"] !== undefined) {
          return {
            facet: filters["facet"],
            values: [{ value: "u1", count: { value: 2, exact: true } }],
          };
        }

        if (filters["count"] === true) {
          return { value: 7, exact: false };
        }

        return { items: [CODE], hasMore: true, nextCursor: ["a", "b"] };
      },
    });

    const block = createReferrals({ transport: t, tenant: "org-1" });

    const page = await block
      .codePage({
        limit: 1,
        sort: { by: "createdAt", direction: "asc" },
        filters: { referrer: ["u1"] },
      })
      .orThrow();

    const facets = await block.codeFacets({ facets: ["referrer"] }).orThrow();
    const count = await block.codeCount().orThrow();

    expect(page.items).toHaveLength(1);
    expect(page).toMatchObject({ hasMore: true, nextCursor: ["a", "b"] });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org-1",
      filters: { limit: 1, sort: "createdAt", direction: "asc", paged: true },
    });
    expect(facets[0]?.facet).toBe("referrer");
    expect(facets[0]?.values[0]?.count).toEqual({ value: 2, exact: true });
    expect(count).toEqual({ value: 7, exact: false });
  });

  it("rejects a sort of referral codes that is not declared", async () => {
    const t = fieldsTransport({});
    const block = createReferrals({ transport: t, tenant: "org-1" });

    const result = await block.codePage({ sort: { by: "nope" } });

    expect(result.ok).toBe(false);
    expect(t.calls).toHaveLength(0);
  });
});
