import { describe, expect, it } from "vitest";

import {
  explainClaims,
  reportFormat,
} from "../../../src/cli/doctor/options.ts";

describe("reportFormat", () => {
  it("falls back to the configured format", () => {
    expect(reportFormat({ format: undefined, json: undefined }, "sarif")).toBe(
      "sarif",
    );
  });

  it("lets --json win and refuses it with --format", () => {
    expect(reportFormat({ format: undefined, json: true }, "text")).toBe(
      "json",
    );
    expect(() => reportFormat({ format: "sarif", json: true }, "text")).toThrow(
      "not both",
    );
  });

  it("rejects an unknown format and the retired json value", () => {
    expect(() =>
      reportFormat({ format: "xml", json: undefined }, "text"),
    ).toThrow("--format must be one of");
    expect(() =>
      reportFormat({ format: "json", json: undefined }, "text"),
    ).toThrow("global --json flag");
  });
});

describe("explainClaims", () => {
  const USER = "0b1c2d3e-0000-4000-8000-000000000001";

  it("defaults to the anon role", () => {
    expect(explainClaims({ as: undefined, claims: undefined })).toEqual({
      role: "anon",
    });
  });

  it("turns --as into an authenticated subject", () => {
    expect(explainClaims({ as: USER, claims: undefined })).toEqual({
      sub: USER,
      role: "authenticated",
    });
    expect(explainClaims({ as: "nope", claims: undefined })).toHaveProperty(
      "error",
    );
  });

  it("parses --claims and refuses both flags together", () => {
    expect(
      explainClaims({ as: undefined, claims: '{"role":"service_role"}' }),
    ).toEqual({ role: "service_role" });
    expect(explainClaims({ as: undefined, claims: "[1]" })).toHaveProperty(
      "error",
    );
    expect(explainClaims({ as: undefined, claims: "{" })).toHaveProperty(
      "error",
    );
    expect(explainClaims({ as: USER, claims: "{}" })).toHaveProperty("error");
  });
});
