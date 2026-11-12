import { describe, expect, it } from "vitest";

import {
  AGENTS_BUDGET_BYTES,
  localLinks,
  pnpmScripts,
  problemsFor,
} from "./check-agent-docs.ts";

describe("pnpmScripts", () => {
  it("names scripts and skips built-in commands", () => {
    expect(
      pnpmScripts("Run `pnpm check`, `pnpm install` and `pnpm db:gen`."),
    ).toEqual(["check", "db:gen"]);
  });
});

describe("localLinks", () => {
  it("skips URLs and anchors", () => {
    expect(
      localLinks("[a](docs/x.md) [b](https://x.dev) [c](#top) [d](y.md#z)"),
    ).toEqual(["docs/x.md", "y.md"]);
  });
});

describe("problemsFor", () => {
  it("passes a small, correct document", () => {
    expect(
      problemsFor(
        { "AGENTS.md": "`pnpm check` [d](docs/x.md)" },
        new Set(["check"]),
        () => true,
      ),
    ).toEqual([]);
  });

  it("reports size, a missing link and a missing script", () => {
    const text = `${"x".repeat(AGENTS_BUDGET_BYTES)} \`pnpm gone\` [d](nope.md)`;

    expect(
      problemsFor({ "AGENTS.md": text }, new Set(), () => false),
    ).toHaveLength(3);
  });
});
