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
});
