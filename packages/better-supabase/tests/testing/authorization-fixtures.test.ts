import { describe, expect, it } from "vitest";

import type { AuthorizationProvider } from "../../src/config/index.ts";

import { permissionsAuthorizer } from "../../src/blocks/permissions/authorizer.ts";
import { providerTruncatedClaim } from "../../src/cli/authorization.ts";
import { testAuthorizationProvider } from "../../src/testing/authorization-provider.ts";
import { testAuthorizer } from "../../src/testing/authorizer.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import {
  ownsPermissionsProvider,
  sharedPermissionsProvider,
  stubProvider,
  withProvider,
} from "../fixtures/authorization-provider.ts";

const user = "00000000-0000-4000-8000-000000000001";

function authorizerFor(provider: AuthorizationProvider) {
  const truncatedClaim = providerTruncatedClaim(provider);

  return permissionsAuthorizer({
    permissions: {},
    ...(truncatedClaim === undefined ? {} : { truncatedClaim }),
  });
}

async function failures(provider: AuthorizationProvider): Promise<string[]> {
  const error = await testAuthorizationProvider(provider).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe.each([
  ["owns permissions", ownsPermissionsProvider],
  ["leaves permissions to better-supabase", sharedPermissionsProvider],
])("a provider that %s", (_, provider) => {
  it("passes testAuthorizationProvider", async () => {
    const report = await testAuthorizationProvider(provider);

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("passes testAuthorizer with its permissions authorizer", async () => {
    const report = await testAuthorizer(authorizerFor(provider), {
      permissions: ["documents.read", "documents.write"],
      unknown: "documents.unknown",
      granted: {
        permission: "documents.read",
        context: {
          actor: { id: user, kind: "user", role: "authenticated" },
          tenant: "org-1",
          claims: { sub: user, permissions: { "org-1": ["documents.read"] } },
        },
      },
    });

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });
});

describe("testAuthorizationProvider on the permissions claim", () => {
  it("refuses two truncated markers that disagree", async () => {
    expect(
      await failures(
        withProvider({
          tokenHook: { ...stubProvider.tokenHook, truncatedClaim: "cut" },
        }),
      ),
    ).toEqual(["names one truncated marker, apart from the claims it marks"]);
  });

  it("refuses a budget over permissions without a marker", async () => {
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            ownedClaims: ["memberships", "permissions"],
            budget: { claims: ["permissions"], bytes: 1024 },
          },
        }),
      ),
    ).toEqual(["names one truncated marker, apart from the claims it marks"]);
  });

  it("refuses a permissions claim without sqlComplete keys", async () => {
    expect(
      await failures({
        ...ownsPermissionsProvider,
        permissions: [{ key: "documents.own", sqlComplete: false }],
      }),
    ).toEqual(['writes "permissions" only with keys complete in SQL']);
  });
});
