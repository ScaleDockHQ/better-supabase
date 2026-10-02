import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import packageJson from "../../package.json" with { type: "json" };
import { problems, validatorFor } from "./validator.ts";

const serverJson = JSON.parse(
  await readFile(new URL("../../../../server.json", import.meta.url), "utf8"),
) as Record<string, unknown>;

describe("MCP Registry server.json", () => {
  it("names the vendored registry schema", () => {
    expect(serverJson["$schema"]).toBe(
      "https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json",
    );
  });

  it("validates against the official server.json schema", () => {
    expect(
      problems(validatorFor("mcp-registry-server-2025-10-17.json"), serverJson),
    ).toEqual([]);
  });

  it("has the package version", () => {
    expect(serverJson["version"]).toBe(packageJson.version);
  });
});
