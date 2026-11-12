import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { describe, expect, it } from "vitest";

import { ROUTES } from "./routes.manifest";

const APP = join(process.cwd(), "src/app/[locale]/(app)");

const pages = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);

    if (statSync(path).isDirectory()) {
      return pages(path);
    }

    return name === "page.tsx" ? [path] : [];
  });

const routeOf = (file: string): string => {
  const folder = relative(APP, join(file, ".."));

  return folder === "" ? "/" : `/${folder.split(sep).join("/")}`;
};

describe("routes manifest", () => {
  const files = pages(APP);

  it("has one entry per page and no entry without a page", () => {
    expect(ROUTES.map((entry) => entry.route).toSorted()).toEqual(
      files.map(routeOf).toSorted(),
    );
  });

  it("states whether each page exports instant", () => {
    for (const file of files) {
      const exports = /export\s+const\s+instant\s*=\s*true/.test(
        readFileSync(file, "utf-8"),
      );

      const entry = ROUTES.find(
        (candidate) => candidate.route === routeOf(file),
      );

      expect(entry?.instant).toBe(exports);
    }
  });

  it("gives every route a positive budget and a url unless it needs an id", () => {
    for (const entry of ROUTES) {
      expect(entry.maxCalls).toBeGreaterThan(0);
      expect(entry.maxWaves).toBeGreaterThan(0);
      expect(entry.url === null).toBe(entry.route.includes("["));
    }
  });
});
