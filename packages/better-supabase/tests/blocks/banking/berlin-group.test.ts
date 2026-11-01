import { describe, expect, it, vi } from "vitest";

import { berlinGroupFeed } from "../../../src/blocks/banking/berlin-group.ts";

const page1 = {
  transactions: {
    booked: [
      {
        transactionId: "t-1",
        bookingDate: "2026-10-01",
        valueDate: "2026-10-02",
        transactionAmount: { currency: "EUR", amount: "-12.50" },
        creditorName: "Shop",
        creditorAccount: { iban: "NL91ABNA0417164300" },
        remittanceInformationUnstructured: "Invoice 42",
        endToEndId: "E2E",
      },
      {
        bookingDate: "2026-10-01",
        transactionAmount: { currency: "EUR", amount: "3.00" },
        debtorName: "Ada",
      },
      { transactionAmount: { currency: "EUR", amount: "1.00" } },
    ],
    _links: { next: { href: "/v1/accounts/a-1/transactions?page=2" } },
  },
};

const page2 = {
  transactions: {
    booked: [
      {
        entryReference: "e-9",
        bookingDate: "2026-10-03",
        transactionAmount: { currency: "EUR", amount: "100" },
        remittanceInformationUnstructuredArray: ["a", "b"],
      },
    ],
  },
};

function bank(handler: (url: string) => Response): {
  feed: ReturnType<typeof berlinGroupFeed>;
  calls: { url: string; headers: Headers }[];
} {
  const calls: { url: string; headers: Headers }[] = [];

  const fetcher = vi.fn(
    async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push({ url: String(input), headers: new Headers(init?.headers) });

      return handler(String(input));
    },
  );

  return {
    calls,
    feed: berlinGroupFeed({
      baseUrl: "https://bank.example/xs2a/v1/",
      consentId: "consent-1",
      headers: async () => ({ authorization: "Bearer t" }),
      fetch: fetcher,
    }),
  };
}

describe("berlinGroupFeed", () => {
  it("lists accounts with the consent header", async () => {
    const { feed, calls } = bank(() =>
      Response.json({
        accounts: [
          {
            resourceId: "a-1",
            iban: "NL91ABNA0417164300",
            currency: "EUR",
            name: "Main",
          },
          { iban: "x" },
        ],
      }),
    );

    const result = await feed.listAccounts();

    expect(result.ok && result.data).toEqual([
      { ref: "a-1", iban: "NL91ABNA0417164300", currency: "EUR", name: "Main" },
    ]);
    expect(calls[0]?.url).toBe("https://bank.example/xs2a/v1/accounts");
    expect(calls[0]?.headers.get("consent-id")).toBe("consent-1");
    expect(calls[0]?.headers.get("authorization")).toBe("Bearer t");
    expect(calls[0]?.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("reads booked transactions across pages and maps the counterparty", async () => {
    const { feed, calls } = bank((url) =>
      Response.json(url.includes("page=2") ? page2 : page1),
    );

    const result = await feed.transactions("a-1", "2026-10-01");

    expect(result.ok).toBe(true);

    if (!result.ok) {
      return;
    }

    expect(calls[0]?.url).toContain("bookingStatus=booked");
    expect(calls[0]?.url).toContain("dateFrom=2026-10-01");
    expect(result.data).toHaveLength(3);
    expect(result.data[0]).toMatchObject({
      externalId: "t-1",
      counterpartyName: "Shop",
      counterpartyIban: "NL91ABNA0417164300",
      remittance: "Invoice 42",
      endToEndId: "E2E",
      valueOn: "2026-10-02",
    });
    expect(result.data[0]?.amount.amount).toBe(-1250n);
    expect(result.data[1]?.counterpartyName).toBe("Ada");
    expect(result.data[2]).toMatchObject({
      externalId: "e-9",
      remittance: "a b",
    });
  });

  it("maps HTTP failures to errors", async () => {
    const denied = await bank(
      () => new Response("no", { status: 401 }),
    ).feed.listAccounts();

    const limited = await bank(
      () => new Response("no", { status: 429 }),
    ).feed.listAccounts();

    expect(!denied.ok && denied.error.kind).toBe("unauthorized");
    expect(!limited.ok && limited.error.kind).toBe("rate_limited");
  });

  it("refuses a next link that leaves the bank's host", async () => {
    const { feed } = bank(() =>
      Response.json({
        transactions: {
          booked: [],
          _links: { next: { href: "https://evil.example/x" } },
        },
      }),
    );

    const result = await feed.transactions("a-1", "2026-10-01");

    expect(result.ok).toBe(false);
  });

  it("stops at the page limit", async () => {
    const calls = { n: 0 };

    const feed = berlinGroupFeed({
      baseUrl: "https://bank.example/v1",
      consentId: "c",
      maxPages: 2,
      fetch: async () => {
        calls.n += 1;

        return Response.json({
          transactions: { booked: [], _links: { next: { href: "/v1/next" } } },
        });
      },
    });

    const result = await feed.transactions("a", "2026-10-01");

    expect(result.ok).toBe(false);
    expect(calls.n).toBe(2);
  });
});
