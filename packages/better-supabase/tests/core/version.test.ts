import { describe, expect, it } from "vitest";

import packageJson from "../../package.json" with { type: "json" };
import { VERSION as CLI_VERSION } from "../../src/cli/version.ts";
import { VERSION } from "../../src/core/version.ts";

describe("VERSION", () => {
  it("matches package.json in the library and the CLI (scripts/sync-versions.ts writes both)", () => {
    expect(VERSION).toBe(packageJson.version);
    expect(CLI_VERSION).toBe(packageJson.version);
  });
});
