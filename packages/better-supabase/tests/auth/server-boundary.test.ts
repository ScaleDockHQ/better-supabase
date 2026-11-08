import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * The adapters run on `@supabase/middleware` bridges. `@supabase/server`'s own
 * `adapters/*` entries are removed on December 1, 2026, and its `allow`,
 * `'always'` and `'public'` auth spellings are the old names for the four modes
 * `user`, `publishable`, `secret` and `none` (plan Part 6).
 */
const SRC = join(import.meta.dirname, "../../src");

function sources(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) {
      return sources(path);
    }

    return /\.tsx?$/u.test(entry.name) ? [path] : [];
  });
}

const files = sources(SRC).map((path) => ({
  path,
  text: readFileSync(path, "utf-8"),
}));

describe("@supabase/server boundary", () => {
  it("never imports the deprecated adapters entries", () => {
    expect(
      files
        .filter((file) => /@supabase\/server\/adapters/u.test(file.text))
        .map((file) => file.path),
    ).toEqual([]);
  });

  it("never passes the legacy auth spellings", () => {
    expect(
      files
        .filter((file) =>
          /\bauth:\s*(?:\[[^\]]*)?["'](?:always|public|allow)["']/u.test(
            file.text,
          ),
        )
        .map((file) => file.path),
    ).toEqual([]);
  });
});
