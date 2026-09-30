import { createClient } from "@supabase/supabase-js";
import { createServer } from "better-supabase/server";
import { createTestSigner } from "better-supabase/testing";
import { afterEach, describe, expect, it, vi } from "vitest";

import { appChrome, customerOverview, portal, sb } from "./latency.ts";

const ORG = "00000000-0000-4000-8000-0000000000aa";
const USER = "11111111-1111-4111-8111-111111111111";
const PROJECT_URL = "https://crm.supabase.co";

type Answer = (url: URL) => unknown;

/** A supabase-js client whose requests are recorded and answered by path. */
function capture(answer: Answer = () => []) {
  const fetch = vi.fn<typeof globalThis.fetch>((input) => {
    const url = new URL(String(input));
    return Promise.resolve(
      Response.json(answer(url), { headers: { "content-range": "0-0/7" } }),
    );
  });
  const urls = () => fetch.mock.calls.map(([input]) => new URL(String(input)));
  return { fetch, urls };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("CRM latency ports", () => {
  it("lists customers with facet counts and aggregates in two parallel calls", async () => {
    const { fetch, urls } = capture((url) =>
      url.searchParams.get("select")?.includes("count()")
        ? [
            { status: "active", isBusiness: true, _count: 5 },
            { status: "prospect", isBusiness: false, _count: 2 },
          ]
        : [],
    );
    const db = sb.connect(
      createClient(PROJECT_URL, "sb_publishable_test", { global: { fetch } }),
    );
    const query = customerOverview.parse(
      new URLSearchParams("q=acme&status=active"),
    );
    if (!query.ok) throw new Error("invalid query");

    const page = await customerOverview
      .run(db, query.value, {
        where: { organizationId: ORG },
        select: ["id", "companyName", "status"],
        include: {
          _count: { customerContacts: true },
          _max: { customerLocationsByCustomer: { updatedAt: true } },
        },
      })
      .orThrow();

    // Each facet's counts apply the other facets' selection, not its own.
    expect(page.facetCounts.status).toMatchObject({ active: 5, prospect: 2 });
    expect(db.$stats()).toMatchObject({ calls: 2, waves: 1 });
    const selects = urls().map((url) => url.searchParams.get("select") ?? "");
    expect(selects.some((select) => select.includes("count()"))).toBe(true);
    expect(selects.some((select) => select.includes("updated_at.max()"))).toBe(
      true,
    );
  });

  it("reads the app-chrome badges as one read set call", async () => {
    const { fetch, urls } = capture((url) =>
      url.pathname.endsWith("/rpc/rs_app_chrome")
        ? {
            unread: { rows: [], count: 3 },
            openTasks: { rows: [], count: 8 },
            approvals: { rows: [], count: 1 },
          }
        : [],
    );
    const db = sb.connect(
      createClient(PROJECT_URL, "sb_publishable_test", { global: { fetch } }),
    );

    const badges = await db.$many(appChrome, { userId: USER }).orThrow();

    expect(badges).toEqual({ unread: 3, openTasks: 8, approvals: 1 });
    expect(db.$stats()).toMatchObject({ calls: 1, waves: 1 });
    const [call] = urls();
    expect(call!.pathname).toBe("/rest/v1/rpc/rs_app_chrome");
    expect(JSON.parse(call!.searchParams.get("p")!)).toEqual({ userId: USER });
  });

  it("scopes portal reads to the customer in the verified claims", async () => {
    const signer = await createTestSigner();
    const { fetch, urls } = capture();
    vi.stubGlobal("fetch", fetch);
    const server = createServer(portal, {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      auth: { jwks: signer.jwks as never },
    });
    const token = await signer.sign({ sub: USER, customer_id: "42" });
    const ctx = await server.context(
      new Request("https://portal.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    if (ctx.auth.kind !== "user") throw new Error("expected a user");
    expect(ctx.auth.claims.customer_id).toBe("42");

    const [invoices, quotes] = await Promise.all([
      ctx.db.invoices
        .findMany({ select: ["id", "status", "totalIncl"], limit: 20 })
        .orThrow(),
      ctx.db.quotes.count().orThrow(),
    ]);

    expect(invoices).toEqual([]);
    expect(quotes).toBe(7);
    expect(ctx.db.$stats()).toMatchObject({ calls: 2, waves: 1 });
    for (const url of urls()) {
      expect(url.searchParams.get("customer_id")).toBe("eq.42");
    }

    const rejected = await server.context(
      new Request("https://portal.test/", {
        headers: {
          authorization: `Bearer ${await signer.sign({ sub: USER })}`,
        },
      }),
    );
    expect(rejected.auth).toMatchObject({ kind: "invalid", reason: "claims" });
  });
});
