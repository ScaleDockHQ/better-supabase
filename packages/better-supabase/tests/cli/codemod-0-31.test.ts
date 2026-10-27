import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const v031 = CODEMODS["0.31"]!;

describe("codemod 0.31", () => {
  it("renames auth.organization to auth.tenant in a TypeScript config", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  auth: {
    // the active organization
    organization: { claim: "org_id", column: "organization_id" },
  },
  $production: { auth: { organization: { onMissing: "skip" } } },
});
`;

    expect(applyCodemod(v031, source, "better-supabase.config.ts").text)
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  auth: {
    // the active organization
    tenant: { claim: "org_id", column: "organization_id" },
  },
  $production: { auth: { tenant: { onMissing: "skip" } } },
});
`);
  });

  it("renames auth.organization in a JSON config", () => {
    const source = JSON.stringify({
      auth: { organization: { claim: "org_id" } },
    });

    expect(
      JSON.parse(
        applyCodemod(v031, source, "better-supabase.config.json").text,
      ),
    ).toEqual({ auth: { tenant: { claim: "org_id" } } });
  });

  it("lists a config that sets both keys for review", () => {
    const source = `export default {
  auth: { organization: { claim: "org_id" }, tenant: { column: "org" } },
};
`;

    const result = applyCodemod(v031, source, "better-supabase.config.ts");

    expect(result.text).toBe(source);
    expect(result.review).toEqual([
      expect.objectContaining({ line: 2 }) as unknown,
    ]);
  });

  it("renames the requireOrganization option and the config type", () => {
    const source = `import type { OrganizationConfig } from "better-supabase/config";

const route = { requireOrganization: true, note: "requireOrganization" };
const tenant: OrganizationConfig = {};
`;

    expect(applyCodemod(v031, source, "src/routes.ts").text)
      .toBe(`import type { TenantConfig } from "better-supabase/config";

const route = { requireTenant: true, note: "requireOrganization" };
const tenant: TenantConfig = {};
`);
  });

  it("renames the session, sign-in and cache methods and the proxy options", () => {
    const source = `import type { OAuthStart } from "better-supabase/next";
import { bsb } from "@/lib/bsb";

const snapshot = await bsb.getRequestSession();
await bsb.invalidateSession(userId);
const { url } = await bsb.authorizeUrl(start satisfies OAuthStart);
await bsb.exchangeCode({ code });
bsb.cacheTags(spec);
bsb.cacheTag("customers");
bsb.proxy(request, { endedSession: true, refreshSkewSeconds: 30, expiredPrefetch: "render" });
`;

    expect(applyCodemod(v031, source, "src/proxy.ts").text)
      .toBe(`import type { SignInWithOAuthParams } from "better-supabase/next";
import { bsb } from "@/lib/bsb";

const snapshot = await bsb.getClaims();
await bsb.evictSession(userId);
const { url } = await bsb.signInWithOAuth(start satisfies SignInWithOAuthParams);
await bsb.exchangeCodeForSession({ code });
bsb.tags(spec);
bsb.tag("customers");
bsb.proxy(request, { verifySession: true, leeway: 30, onExpiredPrefetch: "render" });
`);
  });

  it("lists the session reads, caller kinds and sign-in calls for review", () => {
    const source = `const session = await bsb.session();
if (session.kind === "anon") {}
await bsb.signIn({ email, password });
`;

    expect(
      applyCodemod(v031, source, "src/page.ts")
        .review.map((entry) => entry.line)
        .toSorted((a, b) => a - b),
    ).toEqual([1, 2, 3]);
  });
});
