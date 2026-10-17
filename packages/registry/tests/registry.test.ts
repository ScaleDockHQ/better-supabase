import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

const ROOT = resolve(import.meta.dirname, "..");
const PUBLIC = resolve(ROOT, "../../apps/marketing/public/r");
const VERSION = v.parse(
  v.object({ version: v.string() }),
  JSON.parse(
    readFileSync(resolve(ROOT, "../better-supabase/package.json"), "utf-8"),
  ),
).version;

const PLATFORMS = ["web", "native"];
const FRAMEWORKS = [
  "next",
  "vite",
  "tanstack-start",
  "react-router",
  "hono",
  "expo",
];
/** Glue only (ADR 0031): no markup, no config and no SQL. */
const ITEM_TYPES = [
  "registry:lib",
  "registry:hook",
  "registry:file",
  "registry:item",
];
const TARGET_PREFIX = new Map([
  ["registry:lib", "@lib/"],
  ["registry:hook", "@hooks/"],
  ["registry:file", "~/"],
]);

const File = v.object({
  path: v.string(),
  type: v.string(),
  target: v.string(),
});
const Item = v.object({
  name: v.string(),
  type: v.string(),
  title: v.string(),
  description: v.string(),
  dependencies: v.array(v.string()),
  registryDependencies: v.optional(v.array(v.string()), []),
  files: v.optional(v.array(File), []),
  envVars: v.record(v.string(), v.string()),
  docs: v.string(),
  meta: v.object({
    block: v.union([v.string(), v.array(v.string())]),
    platforms: v.array(v.string()),
    frameworks: v.array(v.string()),
  }),
});
const Registry = v.object({ name: v.string(), items: v.array(Item) });

const registry = v.parse(
  Registry,
  JSON.parse(readFileSync(join(ROOT, "registry.json"), "utf-8")),
);
const names = new Set(registry.items.map((item) => item.name));

describe("registry.json", () => {
  it("is the better-supabase registry with unique item names", () => {
    expect(registry.name).toBe("better-supabase");
    expect(names.size).toBe(registry.items.length);
  });

  describe.each(registry.items.map((item) => [item.name, item] as const))(
    "%s",
    (_name, item) => {
      it("holds glue only", () => {
        expect(ITEM_TYPES).toContain(item.type);
        for (const file of item.files) {
          expect([...TARGET_PREFIX.keys()]).toContain(file.type);
          expect(
            file.target.startsWith(TARGET_PREFIX.get(file.type) ?? ""),
          ).toBe(true);
          expect(file.path).not.toMatch(/\.(sql|tsx|css)$/);
          expect(file.target).not.toMatch(
            /better-supabase\.config|components\.json|supabase\//,
          );
        }
      });

      it("depends on the current better-supabase and its own items only", () => {
        expect(item.dependencies).toContain(`better-supabase@^${VERSION}`);
        for (const dependency of item.registryDependencies) {
          expect(dependency).toMatch(/^@better-supabase\//);
          expect(names).toContain(dependency.slice("@better-supabase/".length));
        }
      });

      it("sets development env values only", () => {
        for (const value of Object.values(item.envVars)) {
          expect(value).not.toMatch(/live|prod/i);
          for (const url of value.match(/[a-z]+:\/\/[^\s/]+/g) ?? []) {
            expect(url).toMatch(/@?(localhost|127\.0\.0\.1)(:\d+)?$/);
          }
        }
      });

      it("links its docs and describes where it runs", () => {
        expect(item.docs).toMatch(/https:\/\/bettersupabase\.com\//);
        expect(item.meta.platforms.length).toBeGreaterThan(0);
        for (const platform of item.meta.platforms) {
          expect(PLATFORMS).toContain(platform);
        }
        expect(item.meta.frameworks.length).toBeGreaterThan(0);
        for (const framework of item.meta.frameworks) {
          expect(FRAMEWORKS).toContain(framework);
        }
      });

      it("names its variant when it runs on one framework", () => {
        const { frameworks, platforms } = item.meta;
        const suffix =
          item.type === "registry:item"
            ? `-(${frameworks.join("|")})`
            : platforms.length === 1 && platforms[0] === "native"
              ? "-native"
              : frameworks.length === 1
                ? `-${frameworks[0] ?? ""}`
                : "";
        expect(item.name).toMatch(new RegExp(`${suffix}$`));
      });
    },
  );
});

describe("apps/marketing/public/r", () => {
  const out = mkdtempSync(join(tmpdir(), "registry-"));
  afterAll(() => {
    rmSync(out, { recursive: true, force: true });
  });

  // Spawning the shadcn CLI takes several seconds on a loaded CI runner.
  it(
    "matches a fresh `shadcn build` (run `pnpm registry:build`)",
    { timeout: 60_000 },
    () => {
      execFileSync(
        join(ROOT, "node_modules/.bin/shadcn"),
        ["build", "./registry.json", "--output", out],
        { cwd: ROOT, stdio: "pipe" },
      );
      const built = readdirSync(out).toSorted();
      expect(readdirSync(PUBLIC).toSorted()).toEqual(built);
      for (const file of built) {
        expect({
          file,
          contents: readFileSync(join(PUBLIC, file), "utf-8"),
        }).toEqual({ file, contents: readFileSync(join(out, file), "utf-8") });
      }
    },
  );
});
