import { createServer } from "better-supabase/server";
import { createTestSigner } from "better-supabase/testing";
import { afterEach, describe, expect, it, vi } from "vitest";

import { portal, staff } from "./portal.ts";

const ORG = "00000000-0000-4000-8000-0000000000aa";
const USER = "11111111-1111-4111-8111-111111111111";
const PROJECT_URL = "https://crm.supabase.co";

/** A fetch that records every request and answers with an empty page of 7 rows. */
function capture() {
  const fetch = vi.fn<typeof globalThis.fetch>(() =>
    Promise.resolve(
      Response.json([], { headers: { "content-range": "0-0/7" } }),
    ),
  );
  vi.stubGlobal("fetch", fetch);
  return () => fetch.mock.calls.map(([input]) => new URL(String(input)));
}

async function setup() {
  const signer = await createTestSigner();
  const options = {
    env: {
      url: PROJECT_URL,
      publishableKey: "sb_publishable_test",
      jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
    },
    auth: { jwks: signer.jwks as never },
  };
  const request = async (claims: Parameters<typeof signer.sign>[0]) =>
    new Request("https://portal.test/", {
      headers: { authorization: `Bearer ${await signer.sign(claims)}` },
    });
  return { options, request };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("contact-scoped and staff reads", () => {
  it("reads a contact's quotes and invoices in one wave, filtered on the customer", async () => {
    const urls = capture();
    const { options, request } = await setup();
    const server = createServer(portal, options);
    const ctx = await server.context(
      await request({ sub: USER, customer_id: "42" }),
    );
    if (ctx.auth.kind !== "user") throw new Error("expected a user");
    expect(ctx.auth.claims.customer_id).toBe("42");

    const [quotes, invoices] = await Promise.all([
      ctx.db.quotes
        .findMany({
          select: ["id", "number", "status", "totalIncl"],
          where: { status: { in: ["sent", "accepted"] } },
          limit: 20,
        })
        .orThrow(),
      ctx.db.invoices.count().orThrow(),
    ]);

    expect(quotes).toEqual([]);
    expect(invoices).toBe(7);
    const stats = ctx.db.$stats();
    expect(stats.calls).toBeLessThanOrEqual(2);
    expect(stats.waves).toBe(1);
    for (const url of urls()) {
      expect(url.searchParams.get("customer_id")).toBe("eq.42");
      expect(url.searchParams.has("organization_id")).toBe(false);
    }

    const rejected = await server.context(await request({ sub: USER }));
    expect(rejected.auth).toMatchObject({ kind: "invalid", reason: "claims" });
  });

  it("reads an employee's quotes and invoices in one wave, filtered on the organization", async () => {
    const urls = capture();
    const { options, request } = await setup();
    const server = createServer(staff, options);
    const ctx = await server.context(
      await request({ sub: USER, organization_id: ORG }),
    );
    if (ctx.auth.kind !== "user") throw new Error("expected a user");

    const [quotes, invoices] = await Promise.all([
      ctx.db.quotes
        .findMany({
          select: ["id", "number", "status", "customerId"],
          orderBy: { issueDate: "desc" },
          limit: 50,
        })
        .orThrow(),
      ctx.db.invoices
        .findMany({
          select: ["id", "formattedNumber", "status", "customerId"],
          where: { status: { neq: "draft" } },
          limit: 50,
        })
        .orThrow(),
    ]);

    expect([quotes, invoices]).toEqual([[], []]);
    const stats = ctx.db.$stats();
    expect(stats.calls).toBeLessThanOrEqual(2);
    expect(stats.waves).toBe(1);
    expect(urls().map((url) => url.pathname)).toEqual([
      "/rest/v1/quotes",
      "/rest/v1/invoices",
    ]);
    for (const url of urls()) {
      expect(url.searchParams.get("organization_id")).toBe(`eq.${ORG}`);
      expect(url.searchParams.has("customer_id")).toBe(false);
    }

    const contactToken = await server.context(
      await request({ sub: USER, customer_id: "42" }),
    );
    expect(contactToken.auth).toMatchObject({
      kind: "invalid",
      reason: "claims",
    });
  });
});
