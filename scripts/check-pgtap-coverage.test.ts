import { describe, expect, it } from "vitest";

import { checkPgtapCoverage, pgtapProblems } from "./check-pgtap-coverage.ts";

describe("pgtapProblems", () => {
  it("accepts a file named after the block or prefixed with it", () => {
    expect(
      pgtapProblems(
        ["assets", "ai-chat", "quotes"],
        ["assets", "ai_chat_sharing", "quote_versions"],
        ["quotes"],
      ),
    ).toEqual([]);
  });

  it("flags a block with SQL and no file", () => {
    expect(pgtapProblems(["assets"], ["asset_tags"], [])).toEqual([
      expect.stringContaining("block assets installs SQL"),
    ]);
  });

  it("flags allowlist entries that are covered or unknown", () => {
    expect(pgtapProblems(["assets"], ["assets"], ["assets", "gone"])).toEqual([
      expect.stringContaining("assets has a pgTAP file now"),
      expect.stringContaining("gone is not a block with SQL"),
    ]);
  });
});

describe("checkPgtapCoverage", () => {
  it("holds for the repository", () => {
    expect(checkPgtapCoverage()).toEqual([]);
  });
});
