import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const PACKAGE = resolve(import.meta.dirname, "../..");
const REPO = resolve(PACKAGE, "../..");

describe("npm provenance", () => {
  it("publishes with provenance from a workflow that can mint an OIDC token", async () => {
    const manifest = JSON.parse(
      await readFile(join(PACKAGE, "package.json"), "utf8"),
    ) as {
      publishConfig?: { provenance?: boolean; access?: string };
    };
    expect(manifest.publishConfig?.provenance).toBe(true);
    const release = await readFile(
      join(REPO, ".github/workflows/release.yml"),
      "utf8",
    );
    expect(release).toMatch(/id-token:\s*write/);
  });
});
