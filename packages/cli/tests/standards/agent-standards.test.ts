import { existsSync, readdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { loadSkills } from "../../src/commands/skills.ts";

/** better-supabase, which ships the skills. */
const PACKAGE = resolve(import.meta.dirname, "../../../better-supabase");
const REPO = resolve(PACKAGE, "../..");
const SKILLS = join(PACKAGE, "skills");

const json = async (path: string): Promise<Record<string, unknown>> =>
  JSON.parse(await readFile(path, "utf8")) as Record<string, unknown>;

/** The YAML frontmatter as flat `key: value` pairs (the spec's fields are scalars or one map). */
function frontmatter(markdown: string): Record<string, string> {
  const block = /^---\n([^]*?)\n---\n/.exec(markdown);
  if (!block) throw new Error("SKILL.md has no frontmatter");
  return Object.fromEntries(
    block[1]!
      .split("\n")
      .filter((line) => /^[a-z-]+:/.test(line))
      .map((line) => {
        const at = line.indexOf(":");
        return [line.slice(0, at), line.slice(at + 1).trim()];
      }),
  );
}

// https://agentskills.io/specification
const SPEC_FIELDS = new Set([
  "name",
  "description",
  "license",
  "compatibility",
  "metadata",
  "allowed-tools",
]);

describe("Agent Skills", () => {
  const folders = readdirSync(SKILLS).filter((name) =>
    existsSync(join(SKILLS, name, "SKILL.md")),
  );

  it("ships at least the core skill", () => {
    expect(folders).toContain("better-supabase");
  });

  it.each(folders)("%s/SKILL.md has spec-valid frontmatter", async (folder) => {
    const fields = frontmatter(
      await readFile(join(SKILLS, folder, "SKILL.md"), "utf8"),
    );
    for (const key of Object.keys(fields)) expect(SPEC_FIELDS).toContain(key);
    expect(fields["name"]).toBe(folder);
    expect(fields["name"]).toMatch(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
    expect(fields["name"]!.length).toBeLessThanOrEqual(64);
    expect(fields["description"]!.length).toBeGreaterThan(0);
    expect(fields["description"]!.length).toBeLessThanOrEqual(1024);
    expect((fields["compatibility"] ?? "").length).toBeLessThanOrEqual(500);
  });

  it.each(folders)("%s links only to files that exist", async (folder) => {
    const body = await readFile(join(SKILLS, folder, "SKILL.md"), "utf8");
    const links = [
      ...body.matchAll(/\]\((?!https?:|#|mailto:)([^)#\s]+)/g),
    ].map((match) => match[1]!);
    expect(
      links.filter((link) => !existsSync(join(SKILLS, folder, link))),
    ).toEqual([]);
  });

  it("the package ships skills/ and the CLI lists every skill", async () => {
    const manifest = await json(join(PACKAGE, "package.json"));
    expect(manifest["files"]).toContain("skills");
    expect(
      (await loadSkills(SKILLS)).map((skill) => skill.name).toSorted(),
    ).toEqual(folders.toSorted());
  });

  it("the Claude and Cursor plugin manifests expose the same skills", async () => {
    const claude = await json(join(REPO, ".claude-plugin/plugin.json"));
    const paths = (claude["skills"] as string[]).map((path) =>
      resolve(REPO, path),
    );
    expect(paths.toSorted()).toEqual(
      folders.map((folder) => join(SKILLS, folder)).toSorted(),
    );
    const cursor = await json(join(REPO, ".cursor-plugin/plugin.json"));
    expect(resolve(REPO, cursor["skills"] as string)).toBe(SKILLS);
    const marketplace = await json(
      join(REPO, ".claude-plugin/marketplace.json"),
    );
    const [plugin] = marketplace["plugins"] as {
      name: string;
      version: string;
      source: string;
    }[];
    expect(plugin!.name).toBe(claude["name"]);
    expect(
      existsSync(join(REPO, plugin!.source, ".claude-plugin/plugin.json")),
    ).toBe(true);
  });

  it("plugin, marketplace and server.json versions match the package version", async () => {
    const { version } = await json(join(PACKAGE, "package.json"));
    const marketplace = await json(
      join(REPO, ".claude-plugin/marketplace.json"),
    );
    expect(
      (await json(join(REPO, ".claude-plugin/plugin.json")))["version"],
    ).toBe(version);
    expect(
      (await json(join(REPO, ".cursor-plugin/plugin.json")))["version"],
    ).toBe(version);
    expect((marketplace["plugins"] as { version: string }[])[0]!.version).toBe(
      version,
    );
    expect((await json(join(REPO, "server.json")))["version"]).toBe(version);
  });
});

describe("AGENTS.md", () => {
  it("lives at the repo root, and CLAUDE.md imports it instead of copying it", async () => {
    const agents = await readFile(join(REPO, "AGENTS.md"), "utf8");
    expect(agents.startsWith("# ")).toBe(true);
    expect((await readFile(join(REPO, "CLAUDE.md"), "utf8")).trim()).toBe(
      "@AGENTS.md",
    );
  });

  it("links only to repo files that exist", async () => {
    const agents = await readFile(join(REPO, "AGENTS.md"), "utf8");
    const links = [...agents.matchAll(/\]\((?!https?:|#)([^)#\s]+)/g)].map(
      (match) => match[1]!,
    );
    expect(links.length).toBeGreaterThan(0);
    expect(links.filter((link) => !existsSync(join(REPO, link)))).toEqual([]);
  });
});

describe("llms.txt", () => {
  const docs = join(REPO, "apps/docs/app");

  it.each(["llms.txt", "llms-full.txt"])("the docs app serves /%s", (route) => {
    expect(existsSync(join(docs, route, "route.ts"))).toBe(true);
  });

  it("the marketing domain rewrites /llms.txt and /llms-full.txt to docs", async () => {
    const vercel = await json(join(REPO, "vercel.json"));
    const text = JSON.stringify(vercel);
    expect(text).toContain('"/llms.txt"');
    expect(text).toContain('"/llms-full.txt"');
    const marketing = await readFile(
      join(REPO, "apps/marketing/next.config.ts"),
      "utf8",
    );
    expect(marketing).toContain('"/llms.txt"');
    expect(marketing).toContain('"/llms-full.txt"');
  });
});
