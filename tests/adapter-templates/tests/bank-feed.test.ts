import { describe, expect, it } from "vitest";

import { createBankFeed } from "../src/bank-feed.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

describe("bank feed", () => {
  const { fetch, calls } = fakeFetch(({ path }) =>
    path.startsWith("/accounts/a1/transactions")
      ? {
          json: {
            transactions: [
              {
                id: "t1",
                booked: "2026-10-30",
                amountMinor: "-1234",
                currency: "EUR",
                remittance: "Invoice 42",
              },
            ],
          },
        }
      : {
          json: {
            accounts: [
              { id: "a1", currency: "EUR", iban: "NL91ABNA0417164300" },
            ],
          },
        },
  );

  const feed = createBankFeed({ ...OPTIONS, fetch });

  it("targets API version 1 and names itself", () => {
    expect(feed.apiVersion).toBe(1);
    expect(feed.name.length).toBeGreaterThan(0);
  });

  it("lists accounts and reads signed transactions with a stable id", async () => {
    const accounts = await feed.listAccounts().orThrow();
    const rows = await feed.transactions("a1", "2026-10-01").orThrow();

    expect(accounts[0]).toMatchObject({ ref: "a1", currency: "EUR" });
    expect(rows[0]).toMatchObject({ externalId: "t1", bookedOn: "2026-10-30" });
    expect(rows[0]?.amount.amount).toBe(-1234n);
    expect(calls.at(-1)?.path).toContain("since=2026-10-01");
    expect(calls.at(-1)?.headers.get("authorization")).toBe("Bearer key");
  });

  it("returns a failed call as an error Result, never a throw", async () => {
    const failing = createBankFeed({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ status: 401, json: { message: "no" } })).fetch,
    });

    const result = await failing.listAccounts();

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.kind).toBe("unauthorized");
  });
});
