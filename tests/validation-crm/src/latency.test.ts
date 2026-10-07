import { createClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import { type Json } from "./generated.ts";
import { appChrome, customerOverview, betterSupabase } from "./latency.ts";

const ORG = "00000000-0000-4000-8000-0000000000aa";
const USER = "11111111-1111-4111-8111-111111111111";
const PROJECT_URL = "https://crm.supabase.co";

type Answer = (url: URL) => Json;

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
    const db = betterSupabase.connect(
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
    expect(db.$stats()).toMatchObject({ calls: 3, waves: 1 });
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
    const db = betterSupabase.connect(
      createClient(PROJECT_URL, "sb_publishable_test", { global: { fetch } }),
    );

    const badges = await db.$many(appChrome, { userId: USER }).orThrow();

    expect(badges).toEqual({ unread: 3, openTasks: 8, approvals: 1 });
    expect(db.$stats()).toMatchObject({ calls: 1, waves: 1 });
    const [call] = urls();
    expect(call!.pathname).toBe("/rest/v1/rpc/rs_app_chrome");
    expect(JSON.parse(call!.searchParams.get("p")!)).toEqual({ userId: USER });
  });
});
