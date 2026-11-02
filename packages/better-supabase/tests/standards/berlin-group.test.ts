import { describe, expect, it } from "vitest";

import { berlinGroupFeed } from "../../src/blocks/banking/berlin-group.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`Berlin Group NextGenPSD2 ${SPEC_PINS.berlinGroupXs2a}`, () => {
  it("reads booked transactions with the headers the framework requires", async () => {
    const calls: { url: string; headers: Headers }[] = [];

    const feed = berlinGroupFeed({
      baseUrl: "https://bank.example/v1",
      consentId: "c-1",
      fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
        calls.push({ url: String(input), headers: new Headers(init?.headers) });

        return Response.json({ transactions: { booked: [] } });
      },
    });

    await feed.transactions("a b", "2026-01-01");

    const url = new URL(calls[0]?.url ?? "https://none.invalid");

    expect(url.pathname).toBe("/v1/accounts/a%20b/transactions");
    expect(url.searchParams.get("bookingStatus")).toBe("booked");
    expect(url.searchParams.get("dateFrom")).toBe("2026-01-01");
    expect(calls[0]?.headers.get("consent-id")).toBe("c-1");
    expect(calls[0]?.headers.get("x-request-id")).toBeTruthy();
  });
});
