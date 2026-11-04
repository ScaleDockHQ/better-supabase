import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";

const contents = (
  names: readonly string[],
  modules: Record<string, object>,
): string =>
  renderBlocks(names, { modules })
    .map((file) => file.contents)
    .join("\n");

describe("blocks that integrate with another block through an option", () => {
  it("attributes a referral to the user who accepts an invitation", () => {
    const sql = contents(["referrals", "invitations"], {
      referrals: { options: { invitations: true } },
    });

    expect(sql).toContain("bsb_referral_invitation");
  });

  it("accrues a commission when an invoice is paid", () => {
    const sql = contents(["commissions", "invoices"], {
      commissions: { options: { invoices: true } },
    });

    expect(sql).toContain("bsb_commission_invoice");
  });

  it("keeps pass credits on the ledger next to bookings", () => {
    const sql = contents(["passes", "bookings", "ledger"], {
      passes: { options: { credits: true } },
    });

    expect(sql).toContain("pass_credit");
  });

  it("names the block a referral integration is missing", () => {
    expect(() =>
      contents(["referrals"], {
        referrals: { options: { invitations: true } },
      }),
    ).toThrow(/needs the invitations block/u);
    expect(() =>
      contents(["commissions"], {
        commissions: { options: { invoices: true } },
      }),
    ).toThrow(/needs the invoices block/u);
  });
});
