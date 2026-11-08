import { describe, expect, it } from "vitest";

import { providerApiProblem } from "../../src/config/authorization.ts";

describe("providerApiProblem", () => {
  it("accepts API version 1", () => {
    expect(providerApiProblem({ name: "x", apiVersion: 1 })).toBeUndefined();
  });

  it("names the provider, or calls an unnamed one provider", () => {
    expect(providerApiProblem({ name: "perms", apiVersion: 2 })).toContain(
      'authorization "perms" targets authorization provider API 2',
    );

    expect(providerApiProblem({ apiVersion: 3 })).toContain(
      'authorization "provider" targets authorization provider API 3',
    );
  });
});
