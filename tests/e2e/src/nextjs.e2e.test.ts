import { instant } from "@next/playwright";
import { type Browser, chromium, type Page } from "@playwright/test";
import { expectDbBudget } from "better-supabase/testing";
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { type AddressInfo, createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import {
  ACME,
  admin,
  createUser,
  OTHER,
  reachable,
  stack,
  type TestUser,
} from "./stack.ts";

const app = fileURLToPath(
  new URL("../../../apps/examples/nextjs/", import.meta.url),
);
const env = {
  ...process.env,
  NEXT_PUBLIC_SUPABASE_URL: stack.url,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
  NEXT_TELEMETRY_DISABLED: "1",
  NEXT_E2E: "1",
};

async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => {
        resolve((address as AddressInfo | null)?.port ?? 0);
      });
    });
  });
}

async function waitFor(url: string, server: ChildProcess): Promise<void> {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null)
      throw new Error(`next start exited with ${String(server.exitCode)}`);
    try {
      await fetch(url, { signal: AbortSignal.timeout(1000) });
      return;
    } catch {
      await new Promise((resolve) => {
        setTimeout(resolve, 250);
      });
    }
  }
  throw new Error(`${url} did not come up`);
}

/** The links in the main menu of a rendered page. */
function menu(html: string): string[] {
  const nav = /<nav aria-label="Main">([\s\S]*?)<\/nav>/.exec(html)?.[1] ?? "";
  return [...nav.matchAll(/<a [^>]*>([^<]*)<\/a>/g)].map((match) => match[1]!);
}

describe.skipIf(!(await reachable()))("nextjs example", () => {
  let server: ChildProcess;
  let base: string;
  let acme: TestUser;
  let member: TestUser;
  let other: TestUser;
  const name = `Next e2e ${crypto.randomUUID()}`;
  let id: string;

  beforeAll(async () => {
    // Always rebuild: the e2e build exposes the instant-navigation testing API.
    execFileSync("pnpm", ["exec", "next", "build"], {
      cwd: app,
      env,
      stdio: "ignore",
    });
    const port = await freePort();
    base = `http://127.0.0.1:${String(port)}`;
    server = spawn(
      "pnpm",
      ["exec", "next", "start", "-p", String(port), "-H", "127.0.0.1"],
      {
        cwd: app,
        env,
        stdio: "ignore",
      },
    );
    [acme, member, other] = await Promise.all([
      createUser(ACME, { role: "admin" }),
      createUser(ACME, { role: "member" }),
      createUser(OTHER, { role: "admin" }),
    ]);
    const { data, error } = await admin
      .from("customers")
      .insert({ name, organization_id: ACME })
      .select("id")
      .single();
    if (error) throw error;
    id = data.id;
    await waitFor(base, server);
  });

  afterAll(async () => {
    server.kill();
    if (id) await admin.from("customers").delete().eq("id", id);
    await Promise.all([acme.remove(), member.remove(), other.remove()]);
  });

  const get = (
    path: string,
    headers: Record<string, string> = {},
    init: RequestInit = {},
  ) => fetch(`${base}${path}`, { headers, ...init });

  it("sends signed-out visitors to the login page", async () => {
    const response = await get("/customers", {}, { redirect: "manual" });
    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("/login");
    expect(await (await get("/")).text()).toContain("Sign in");
  });

  it("renders the signed-in user’s customers in a Server Component", async () => {
    const page = await get("/customers", { cookie: await acme.cookie() });
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain(name);
    expect(html).toContain("New customer");
    // Relation aggregates and the grouped status count render with the rows.
    expect(html).toMatch(/\d+(?:<!-- -->)? notes/);
    expect(html).toMatch(/\d+ (?:lead|active|archived)/);
    // Nearest first, from `db.$search` over the seeded note embeddings.
    const similar = html.slice(html.indexOf('data-testid="similar-notes"'));
    expect(similar.indexOf("Sent the invoice")).toBeGreaterThan(0);
    expect(similar.indexOf("Sent the invoice")).toBeLessThan(
      similar.indexOf("Kickoff"),
    );
    expect(
      await (await get("/customers", { cookie: await other.cookie() })).text(),
    ).not.toContain(name);
  });

  it("shows each role only the menu items and pages it may open", async () => {
    const adminMenu = menu(
      await (await get("/", { cookie: await acme.cookie() })).text(),
    );
    expect(adminMenu).toHaveLength(10);

    const memberCookie = await member.cookie();
    const memberHtml = await (await get("/", { cookie: memberCookie })).text();
    expect(menu(memberHtml)).toEqual([
      "Dashboard",
      "Customers",
      "Inbox",
      "Calendar",
      "Profile",
    ]);

    const customers = await (
      await get("/customers", { cookie: memberCookie })
    ).text();
    expect(customers).toContain(name);
    expect(customers).not.toContain("New customer");

    const users = await get(
      "/users",
      { cookie: memberCookie },
      { redirect: "manual" },
    );
    expect(users.status).toBe(307);
    expect(users.headers.get("location")).toBe("/");
  });

  it("serves route handlers with bearer tokens and Problem Details", async () => {
    const list = await get(`/api/customers?q=${encodeURIComponent(name)}`, {
      authorization: `Bearer ${acme.accessToken}`,
    });
    expect(await list.json()).toEqual([
      { id, name, status: "lead", organizationId: ACME },
    ]);

    const hidden = await get(`/api/customers/${id}`, {
      authorization: `Bearer ${other.accessToken}`,
    });
    expect(hidden.status).toBe(404);
    expect(hidden.headers.get("content-type")).toContain(
      "application/problem+json",
    );

    const anonymous = await get("/api/customers");
    expect(anonymous.status).toBe(401);
  });

  it("requires a second factor to delete through the route handler", async () => {
    const response = await get(
      `/api/customers/${id}`,
      { authorization: `Bearer ${acme.accessToken}` },
      { method: "DELETE" },
    );
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      kind: "forbidden",
      code: "INSUFFICIENT_AAL",
      required: "aal2",
    });
    const { data } = await admin.from("customers").select("id").eq("id", id);
    expect(data).toHaveLength(1);
  });

  it("lists with facet counts in two calls and one wave", async () => {
    const response = await get("/api/customers/list?status=archived", {
      authorization: `Bearer ${acme.accessToken}`,
    });
    expect(response.status).toBe(200);
    const [calls, waves] = response.headers.get("x-bs-db-calls")!.split(";");
    expect([calls, waves]).toEqual(["2", "1"]);
    const page = (await response.json()) as {
      items: { id: string }[];
      facetCounts: { status: Record<string, number> };
    };
    // The status filter hides the new lead, but its facet count stays.
    expect(page.items.map((item) => item.id)).not.toContain(id);
    expect(page.facetCounts.status["lead"]).toBeGreaterThan(0);

    const invalid = await get("/api/customers/list?status=bogus", {
      authorization: `Bearer ${acme.accessToken}`,
    });
    expect(invalid.status).toBe(400);
  });

  describe("instant navigation", () => {
    let browser: Browser;
    let page: Page;

    beforeAll(async () => {
      browser = await chromium.launch();
      const context = await browser.newContext();
      await context.addCookies(
        (await member.cookie()).split("; ").map((pair) => {
          const at = pair.indexOf("=");
          return {
            name: pair.slice(0, at),
            value: pair.slice(at + 1),
            url: base,
          };
        }),
      );
      page = await context.newPage();
    });

    afterAll(async () => {
      await browser.close();
    });

    it("serves a static shell on a cold load, auth streams in after", async () => {
      await instant(
        page,
        async () => {
          await page.goto(`${base}/inbox`);
          await page.getByRole("heading", { name: "Inbox" }).waitFor();
          expect(
            await page
              .locator('nav[aria-label="Main"][aria-busy="true"]')
              .count(),
          ).toBe(1);
          expect(await page.getByText(member.email).count()).toBe(0);
        },
        { baseURL: base },
      );
      const nav = page.getByRole("navigation", { name: "Main" });
      await nav.getByRole("link", { name: "Customers" }).waitFor();
      expect(await nav.getByRole("link").count()).toBe(5);
      await page.getByText(member.email).waitFor();
    });

    it("navigates instantly into session data from the per-session App Shell", async () => {
      const nav = page.getByRole("navigation", { name: "Main" });
      // Let the prefetch of /customers land before the click.
      await page.waitForLoadState("networkidle");
      await instant(page, async () => {
        await nav.getByRole("link", { name: "Customers" }).click();
        await page.waitForURL((url) => url.pathname === "/customers");
        await page.getByRole("heading", { name: "Customers" }).waitFor();
        await page.getByText(name).waitFor({ timeout: 5000 });
      });
    });

    it("renders the customers page within its database budget", async () => {
      const renders = await expectDbBudget(page, {
        maxCalls: 8,
        maxWaves: 2,
        during: () => page.goto(`${base}/customers`),
      });
      expect(renders[0]!.stats.calls).toBeGreaterThan(0);
    });

    it("renders the dashboard read set within one database call", async () => {
      await expectDbBudget(page, {
        maxCalls: 1,
        maxWaves: 1,
        during: () => page.goto(`${base}/`),
      });
      await page.getByTestId("workspace-summary").waitFor();
    });

    it("keeps the unread badge live over Realtime", async () => {
      await page.goto(`${base}/inbox`);
      const summary = page.getByTestId("unread-summary");
      await summary.getByText(/^\d+ unread$/).waitFor();
      await page
        .locator('[data-testid="unread-badge"][data-status="subscribed"]')
        .waitFor({ timeout: 10_000 });
      const badge = page.getByTestId("unread-count");
      await expect.poll(() => badge.textContent()).toMatch(/^\d+$/);
      const before = Number(await badge.textContent());

      // Written outside the app: only Realtime can tell the page.
      const { error } = await admin.from("notifications").insert({
        organization_id: ACME,
        user_id: member.id,
        title: "e2e",
      });
      if (error) throw error;
      await expect
        .poll(() => badge.textContent(), { timeout: 10_000 })
        .toBe(String(before + 1));
      await expect
        .poll(() => summary.textContent(), { timeout: 10_000 })
        .toBe(`${String(before + 1)} unread`);

      await page.getByRole("button", { name: "Mark all read" }).click();
      await expect
        .poll(() => badge.textContent(), { timeout: 10_000 })
        .toBe("0");
    });
  });
});
