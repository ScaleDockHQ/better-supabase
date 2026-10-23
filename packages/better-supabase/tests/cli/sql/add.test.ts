import { describe, expect, it } from "vitest";

import { integratingModules } from "../../../src/cli/sql/add.ts";

describe("integratingModules", () => {
  it("names the installed modules that integrate with a new one", () => {
    expect(
      integratingModules(
        ["organizations", "entitlements", "tags"],
        ["billing", "organizations"],
      ),
    ).toEqual([{ name: "entitlements", with: ["billing"] }]);
  });

  it("skips modules that were already installed", () => {
    expect(integratingModules(["organizations", "audit"], ["audit"])).toEqual(
      [],
    );
  });
});
