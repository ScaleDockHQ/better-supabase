import { AxeBuilder } from "@axe-core/playwright";
import { instant } from "@next/playwright";
import { type Browser, chromium } from "@playwright/test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildAndStart, type NextServer } from "./next-server.ts";

const apps = {
  docs: fileURLToPath(new URL("../../../apps/docs/", import.meta.url)),
  marketing: fileURLToPath(
    new URL("../../../apps/marketing/", import.meta.url),
  ),
};
const env = {
  ...process.env,
  NEXT_TELEMETRY_DISABLED: "1",
  EXPOSE_TESTING_API: "1",
};

const viewports = {
  mobile: { width: 390, height: 844 },
  desktop: { width: 1280, height: 800 },
};

const pages = {
  docs: ["/docs", "/docs/getting-started", "/docs/repository", "/docs/cli"],
  marketing: ["/", "/changelog", "/enterprise"],
};

interface PrerenderManifest {
  readonly routes: Readonly<Record<string, { srcRoute: string | null }>>;
  readonly dynamicRoutes: Readonly<Record<string, { renderingMode?: string }>>;
}

function readManifest<T>(app: string, file: string): T {
  return JSON.parse(readFileSync(join(app, ".next", file), "utf8")) as T;
}

/** Page routes that neither prerender fully nor ship a partial shell. */
function routesWithoutShell(app: string): string[] {
  const routes = readManifest<Record<string, string>>(
    app,
    "app-path-routes-manifest.json",
  );
  const prerender = readManifest<PrerenderManifest>(
    app,
    "prerender-manifest.json",
  );
  return Object.entries(routes)
    .filter(([path]) => path.endsWith("/page"))
    .map(([, route]) => route)
    .filter(
      (route) =>
        !(route in prerender.routes) &&
        prerender.dynamicRoutes[route]?.renderingMode !== "PARTIALLY_STATIC",
    );
}

describe("docs and marketing", () => {
  const servers: Partial<Record<keyof typeof apps, NextServer>> = {};
  let browser: Browser | undefined;

  const newPage = async (viewport: { width: number; height: number }) => {
    if (browser === undefined) throw new Error("Chromium did not launch");
    // axe needs a page from an explicit context.
    const context = await browser.newContext({ viewport });
    return context.newPage();
  };

  const base = (app: keyof typeof apps): string => {
    const server = servers[app];
    if (server === undefined) throw new Error(`${app} is not running`);
    return server.base;
  };

  beforeAll(async () => {
    // Build with the instant-navigation testing API exposed.
    const [docs, marketing] = await Promise.all([
      buildAndStart(apps.docs, env),
      buildAndStart(apps.marketing, env),
    ]);
    servers.docs = docs;
    servers.marketing = marketing;
    browser = await chromium.launch();
  }, 300_000);

  afterAll(async () => {
    await browser?.close();
    servers.docs?.process.kill();
    servers.marketing?.process.kill();
  });

  it.each(Object.keys(apps) as (keyof typeof apps)[])(
    "ships a prerendered shell for every %s route",
    (app) => {
      expect(routesWithoutShell(apps[app])).toEqual([]);
    },
  );

  describe.each(Object.entries(viewports))("axe at %s width", (_, viewport) => {
    it.each(
      Object.entries(pages).flatMap(([app, paths]) =>
        paths.map((path) => [app as keyof typeof apps, path] as const),
      ),
    )("%s %s has no violations", async (app, path) => {
      const page = await newPage(viewport);
      try {
        await page.goto(`${base(app)}${path}`);
        await page.waitForLoadState("networkidle");
        const { violations } = await new AxeBuilder({ page })
          .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
          .analyze();
        expect(
          violations.map((violation) => ({
            id: violation.id,
            nodes: violation.nodes.map((node) => node.target.join(" ")),
          })),
        ).toEqual([]);
      } finally {
        await page.context().close();
      }
    });
  });

  it("navigates instantly between docs pages", async () => {
    const page = await newPage(viewports.desktop);
    try {
      await page.goto(`${base("docs")}/docs/getting-started`);
      await page.waitForLoadState("networkidle");
      await instant(page, async () => {
        await page
          .getByRole("complementary")
          .getByRole("link", { name: "Testing", exact: true })
          .click();
        await page.waitForURL((url) => url.pathname === "/docs/testing");
        await page
          .getByRole("heading", { level: 1, name: "Testing" })
          .waitFor();
      });
    } finally {
      await page.context().close();
    }
  });

  it("navigates instantly from the home page to the changelog", async () => {
    const page = await newPage(viewports.desktop);
    try {
      await page.goto(base("marketing"));
      await page.waitForLoadState("networkidle");
      await instant(page, async () => {
        await page
          .getByRole("navigation", { name: "Main" })
          .getByRole("link", { name: "Changelog" })
          .click();
        await page.waitForURL((url) => url.pathname === "/changelog");
        await page
          .getByRole("heading", { level: 1, name: "Changelog" })
          .waitFor();
      });
    } finally {
      await page.context().close();
    }
  });
});
