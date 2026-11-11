import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import packageJson from "../package.json" with { type: "json" };

describe("api/naming.json", () => {
  it("resolves through the package's own name", async () => {
    const path = fileURLToPath(
      import.meta.resolve("better-supabase/api/naming.json"),
    );

    const naming = JSON.parse(await readFile(path, "utf-8")) as {
      renames: unknown[];
    };

    expect(naming.renames.length).toBeGreaterThan(0);
  });

  it("is in the exports map and the packed files", () => {
    expect(packageJson.exports["./api/naming.json"]).toBe("./api/naming.json");

    const packed = JSON.parse(
      execFileSync("pnpm", ["pack", "--dry-run", "--json"], {
        cwd: fileURLToPath(new URL("..", import.meta.url)),
        encoding: "utf-8",
      }),
    ) as { files: { path: string }[] } | { files: { path: string }[] }[];

    expect(
      (Array.isArray(packed) ? packed[0] : packed)?.files.map(
        (file) => file.path,
      ),
    ).toContain("api/naming.json");
  });
});
