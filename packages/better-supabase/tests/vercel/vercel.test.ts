import { describe, expect, it } from "vitest";

import {
  PROTECTION_BYPASS_HEADER,
  assertDeployment,
  deploymentIssues,
  deploymentUrl,
  protectionBypassHeaders,
  protectionBypassUrl,
  vercelEnvironment,
} from "../../src/vercel/vercel.ts";

const PREVIEW = {
  VERCEL_ENV: "preview",
  VERCEL_PROJECT_PRODUCTION_URL: "app.example.com",
  VERCEL_BRANCH_URL: "app-git-feature-team.vercel.app",
  VERCEL_URL: "app-abc123-team.vercel.app",
};

const PRODUCTION = { ...PREVIEW, VERCEL_ENV: "production" };

describe("vercelEnvironment", () => {
  it("prefers VERCEL_TARGET_ENV and ignores empty values", () => {
    expect(
      vercelEnvironment({
        VERCEL_TARGET_ENV: "staging",
        VERCEL_ENV: "preview",
      }),
    ).toBe("staging");
    expect(
      vercelEnvironment({ VERCEL_TARGET_ENV: "", VERCEL_ENV: "preview" }),
    ).toBe("preview");
    expect(vercelEnvironment({})).toBeUndefined();
  });
});

describe("deploymentUrl", () => {
  it("returns the production domain on production", () => {
    expect(deploymentUrl(PRODUCTION)).toBe("https://app.example.com");
  });

  it("returns the branch URL on a preview, not the production domain", () => {
    expect(deploymentUrl(PREVIEW, { path: "/auth/callback" })).toBe(
      "https://app-git-feature-team.vercel.app/auth/callback",
    );
  });

  it("chooses a target and adds the leading slash", () => {
    expect(deploymentUrl(PREVIEW, { target: "deployment", path: "x" })).toBe(
      "https://app-abc123-team.vercel.app/x",
    );
    expect(deploymentUrl(PREVIEW, { target: "production" })).toBe(
      "https://app.example.com",
    );
    expect(deploymentUrl(PREVIEW, { target: "branch" })).toBe(
      "https://app-git-feature-team.vercel.app",
    );
  });

  it("falls back to VERCEL_URL and strips a scheme", () => {
    expect(
      deploymentUrl({
        VERCEL_ENV: "preview",
        VERCEL_URL: "https://a.vercel.app/",
      }),
    ).toBe("https://a.vercel.app");
  });

  it("returns the fallback, or undefined, outside Vercel", () => {
    expect(deploymentUrl({}, { fallback: "http://localhost:3000" })).toBe(
      "http://localhost:3000",
    );
    expect(deploymentUrl({})).toBeUndefined();
  });

  it("throws on a target outside the union", () => {
    expect(() =>
      // SAFETY: the test passes an invalid target on purpose.
      deploymentUrl(PREVIEW, { target: "nope" as "auto" }),
    ).toThrow(TypeError);
  });
});

describe("protectionBypassHeaders", () => {
  const secret = { VERCEL_AUTOMATION_BYPASS_SECRET: "s3cret" };

  it("is empty without a secret", () => {
    expect(protectionBypassHeaders(PREVIEW)).toEqual({});
  });

  it("returns the header when no URL is given", () => {
    expect(protectionBypassHeaders(secret)).toEqual({
      [PROTECTION_BYPASS_HEADER]: "s3cret",
    });
  });

  it("adds the header only for a host of this deployment", () => {
    const source = { ...PREVIEW, ...secret };

    expect(
      protectionBypassHeaders(source, {
        url: "https://app-abc123-team.vercel.app/q",
      }),
    ).toEqual({ "x-vercel-protection-bypass": "s3cret" });
    expect(
      protectionBypassHeaders(source, { url: "https://APP.example.com/q" }),
    ).toEqual({ "x-vercel-protection-bypass": "s3cret" });
    expect(
      protectionBypassHeaders(source, { url: "https://hooks.other.com/q" }),
    ).toEqual({});
    expect(protectionBypassHeaders(source, { url: "not a url" })).toEqual({});
  });

  it("allows named hosts and an explicit secret", () => {
    expect(
      protectionBypassHeaders(PREVIEW, {
        url: "https://second.example.com",
        allowHosts: ["Second.example.com"],
        secret: "own",
      }),
    ).toEqual({ "x-vercel-protection-bypass": "own" });
  });
});

describe("protectionBypassUrl", () => {
  it("adds the secret as a query parameter for an own host", () => {
    expect(
      protectionBypassUrl("https://app.example.com/hook?a=1", {
        ...PREVIEW,
        VERCEL_AUTOMATION_BYPASS_SECRET: "s3cret",
      }),
    ).toBe(
      "https://app.example.com/hook?a=1&x-vercel-protection-bypass=s3cret",
    );
  });

  it("returns the URL unchanged for another host or without a secret", () => {
    const url = "https://other.com/hook";

    expect(
      protectionBypassUrl(url, { VERCEL_AUTOMATION_BYPASS_SECRET: "s3cret" }),
    ).toBe(url);
    expect(protectionBypassUrl(url, PREVIEW)).toBe(url);
  });
});

describe("deploymentIssues and assertDeployment", () => {
  const ref = "abcdefghijklmnopqrst";
  const production = { SUPABASE_URL: `https://${ref}.supabase.co` };

  it("reports a preview that points at the production project", () => {
    const issues = deploymentIssues(
      { ...PREVIEW, ...production },
      { productionProjectRef: ref },
    );

    expect(issues).toHaveLength(1);
    expect(issues[0]?.variables).toContain("SUPABASE_URL");
    expect(JSON.stringify(issues)).not.toContain(ref);
  });

  it("accepts production, another project and a missing ref", () => {
    expect(
      deploymentIssues(
        { ...PRODUCTION, ...production },
        { productionProjectRef: ref },
      ),
    ).toEqual([]);
    expect(
      deploymentIssues(
        {
          ...PREVIEW,
          SUPABASE_URL: "https://zzzzzzzzzzzzzzzzzzzz.supabase.co",
        },
        { productionProjectRef: ref },
      ),
    ).toEqual([]);
    expect(deploymentIssues({ ...PREVIEW, ...production })).toEqual([]);
    expect(deploymentIssues(production, { productionProjectRef: ref })).toEqual(
      [],
    );
  });

  it("reads a prefixed URL", () => {
    expect(
      deploymentIssues(
        { ...PREVIEW, DB1_SUPABASE_URL: production.SUPABASE_URL },
        { productionProjectRef: ref, prefix: "DB1" },
      ),
    ).toHaveLength(1);
  });

  it("throws an EnvValidationError", () => {
    expect(() => {
      assertDeployment(
        { ...PREVIEW, ...production },
        { productionProjectRef: ref },
      );
    }).toThrow(/production project/);
    expect(() => {
      assertDeployment(PREVIEW, { productionProjectRef: ref });
    }).not.toThrow();
  });
});
