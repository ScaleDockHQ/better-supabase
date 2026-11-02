import { describe, expect, it } from "vitest";

import { createBanking } from "../../../src/blocks/banking/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const UNMATCHED = (id: string) => ({
  id,
  organizationId: "org-1",
  accountId: "a1",
  bookedOn: "2026-10-01",
  amount: "24200",
  currency: "EUR",
  externalId: `BANK-${id}`,
  status: "unmatched",
  matches: [],
  createdAt: AT,
  updatedAt: AT,
});

const SUGGESTION = (score: number, targetType = "invoice") => ({
  targetType,
  targetId: `${targetType}-1`,
  label: "INV-2026-0042",
  balance: "24200",
  currency: "EUR",
  score,
  reasons: ["amount"],
});

function setup(suggestions: Record<string, readonly unknown[]>) {
  const t = fieldsTransport({
    list_bank_transactions: () => [UNMATCHED("t1"), UNMATCHED("t2")],
    suggest_bank_matches: (args) =>
      suggestions[String(args["transaction_id"])] ?? [],
    match_bank_transaction: () => ({ ...UNMATCHED("t1"), status: "matched" }),
  });

  return { t, banking: createBanking({ transport: t, tenant: "org-1" }) };
}

describe("banking helpers", () => {
  it("reviewQueue pairs unmatched transactions with their best invoice", async () => {
    const { t, banking } = setup({
      t1: [SUGGESTION(90, "accounting_entry"), SUGGESTION(50)],
    });

    const queue = await banking.reviewQueue({ accountId: "a1" }).orThrow();

    expect(queue.map((item) => item.transaction.id)).toEqual(["t1", "t2"]);
    expect(queue[0]?.suggestion?.targetId).toBe("invoice-1");
    expect(queue[1]?.suggestion).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "list_bank_transactions",
      { account_id: "a1", filter: { status: "unmatched", limit: 20 } },
    ]);
  });

  it("acceptBestMatch matches the best invoice", async () => {
    const { t, banking } = setup({ t1: [SUGGESTION(120)] });

    await banking.acceptBestMatch({ transactionId: "t1" }).orThrow();

    expect(t.calls.at(-1)).toEqual([
      "match_bank_transaction",
      {
        transaction_id: "t1",
        matches: [{ targetType: "invoice", targetId: "invoice-1" }],
      },
    ]);
  });

  it("acceptBestMatch refuses a weak candidate and matches nothing", async () => {
    const { t, banking } = setup({ t1: [SUGGESTION(40)] });

    const result = await banking.acceptBestMatch({
      transactionId: "t1",
      minScore: 100,
    });

    expect(result.ok ? undefined : result.error).toMatchObject({
      hint: "BANK_NO_MATCH",
    });

    expect(t.calls.map(([fn]) => fn)).not.toContain("match_bank_transaction");
  });
});
