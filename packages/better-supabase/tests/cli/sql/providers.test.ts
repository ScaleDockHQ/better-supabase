import { describe, expect, it } from "vitest";

import { providerOwnsMemberships } from "../../../src/cli/sql/providers.ts";
import { resolveConfig } from "../../../src/config/index.ts";

describe("providerOwnsMemberships", () => {
  it("is false without an authorization provider", () => {
    expect(providerOwnsMemberships(resolveConfig({}, "/project"))).toBe(false);
  });
});
