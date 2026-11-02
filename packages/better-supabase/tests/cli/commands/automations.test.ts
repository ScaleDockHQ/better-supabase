import { describe, expect, it } from "vitest";

import { listAutomations } from "../../../src/cli/commands/automations.ts";

describe("automations list", () => {
  it("lists the automations of the named blocks", () => {
    const result = listAutomations(["quotes"], false);

    expect(result.output).toContain("quotes/");
    expect(result.output).toContain("off by default");
  });

  it("says what starts an automation and what runs with --explain", () => {
    const result = listAutomations(["quotes"], true);

    expect(result.output).toContain("When:");
    expect(result.output).toContain("Then:");
  });

  it("points at --all when no installed block ships one", () => {
    expect(listAutomations(["comments"], false).output).toContain("--all");
  });

  it("lists every block's with no names", () => {
    expect(listAutomations(undefined, false).output).toContain("\n");
  });
});
