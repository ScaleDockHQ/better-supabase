import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const FEATURES = join(process.cwd(), "src/features");

const read = (path: string): string => readFileSync(path, "utf-8");

const domains = readdirSync(FEATURES, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name);

const filesOf = (domain: string): string[] =>
  readdirSync(join(FEATURES, domain), { recursive: true, encoding: "utf-8" })
    .filter((name) => /\.tsx?$/u.test(name))
    .map((name) => join(FEATURES, domain, name));

const ALL = domains.flatMap(filesOf);

/** `export const NAME = tagFor("tag")` in the `*-cache.ts` files: name to tag. */
const TAGS = new Map<string, string>();

for (const path of ALL.filter((file) => file.endsWith("-cache.ts"))) {
  for (const match of read(path).matchAll(
    /export const (\w+) = tagFor\("([^"]+)"\)/gu,
  )) {
    TAGS.set(match[1] ?? "", match[2] ?? "");
  }
}

const kebab = (name: string): string =>
  name.replaceAll(/[A-Z]/gu, (letter) => `-${letter.toLowerCase()}`);

const WRITE =
  /\b(?:db|tx|bsb\.admin\(\))\.(\w+)\.(?:insert|update|delete|upsert|create|remove|insertMany|updateMany|deleteMany|restore|archive|replace)\b/gu;

const CALL = /refreshCaller\(\s*[\w.]+\s*,\s*\[([^\]]*)\]/gu;

interface Use {
  readonly file: string;
  readonly names: readonly string[];
  readonly written: readonly string[];
}

const USES: Use[] = ALL.filter((file) => file.endsWith("-actions.ts")).flatMap(
  (file) => {
    const text = read(file);

    const written = [
      ...new Set([...text.matchAll(WRITE)].map((m) => m[1] ?? "")),
    ];

    return [...text.matchAll(CALL)].map((call) => ({
      file: file.slice(FEATURES.length + 1),
      names: (call[1] ?? "")
        .split(",")
        .map((name) => name.trim())
        .filter(Boolean),
      written,
    }));
  },
);

const READERS = ALL.filter(
  (file) => !file.endsWith("-actions.ts") && !file.endsWith("-cache.ts"),
)
  .map(read)
  .join("\n");

// Ratchets: today's findings, which can shrink and never grow. A write whose
// table has a domain tag of its own (`customers` writes to `shareLinks`, and
// `share-links` is a tag) must expire that tag in the same file, and a tag a
// write passes must be one some read carries, or it expires nothing.
const UNCOVERED_WRITES = 0;
const UNREAD_TAGS = 0;

describe("refreshCaller tags", () => {
  it("finds the calls it checks", () => {
    expect(USES.length).toBeGreaterThan(100);
    expect(TAGS.size).toBeGreaterThan(60);
    expect(USES.filter((use) => use.written.length > 0).length).toBeGreaterThan(
      40,
    );
  });

  it("passes only tags a read carries", () => {
    const unread = USES.flatMap((use) =>
      use.names
        .filter((name) => TAGS.has(name) && !READERS.includes(name))
        .map((name) => `${use.file}: ${name}`),
    );

    expect(unread.slice(UNREAD_TAGS)).toStrictEqual([]);
  });

  it("expires the domain tag of every table an action writes", () => {
    const tagged = new Map([...TAGS].map(([name, tag]) => [tag, name]));

    const missing = USES.flatMap((use) => {
      const passed = new Set(use.names);
      const file = USES.filter((entry) => entry.file === use.file);
      const union = new Set(file.flatMap((entry) => entry.names));

      return use.written.flatMap((table) => {
        const name = tagged.get(kebab(table)) ?? tagged.get(table);

        return name !== undefined && !union.has(name) && !passed.has(name)
          ? [`${use.file}: writes ${table}, passes no ${name}`]
          : [];
      });
    });

    const unique = [...new Set(missing)];

    expect(unique.slice(UNCOVERED_WRITES)).toStrictEqual([]);
  });
});
