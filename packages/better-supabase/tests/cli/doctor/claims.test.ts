import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";
import type { AuthorizationProvider } from "../../../src/config/index.ts";

import { CLAIM_RULES } from "../../../src/cli/doctor/claims.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { stubProvider } from "../../fixtures/authorization-provider.ts";

const authorizerFile: TextFile = {
  path: "src/lib/authz.ts",
  text: 'import { permissionsAuthorizer } from "better-supabase/blocks/permissions";\n\nexport const authorizer = permissionsAuthorizer({ tenantClaim: "tenant_id" });\n',
};

function check(
  provider: AuthorizationProvider | undefined,
  sources: TextFile[] = [authorizerFile],
): string[] {
  const [rule] = CLAIM_RULES;

  const config = resolveConfig(
    provider ? { auth: { authorization: provider } } : {},
    "/project",
  );

  // SAFETY: BS419 reads only `config` and `sources`.
  const context = { config, sources } as unknown as DoctorContext;
  const findings = rule?.check(context);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS419 runs synchronously");
  }

  return findings.map((finding: { message: string }) => finding.message);
}

describe("BS419", () => {
  it("names the keys the permissions claim leaves out", () => {
    const [message, ...rest] = check(stubProvider);

    expect(rest).toEqual([]);
    expect(message).toContain("src/lib/authz.ts");
    expect(message).toContain("documents.own");
    expect(message).not.toContain("documents.read");
  });

  it("reports a provider that lists no permissions", () => {
    const { permissions: _permissions, ...unlisted } = stubProvider;

    expect(check(unlisted)).toEqual([
      expect.stringContaining("lists no permissions"),
    ]);
  });

  it("skips complete providers, no provider and files without the authorizer", () => {
    const complete: AuthorizationProvider = {
      ...stubProvider,
      permissions: (stubProvider.permissions ?? []).map((permission) => ({
        ...permission,
        sqlComplete: true,
      })),
    };

    expect(check(complete)).toEqual([]);
    expect(check(undefined)).toEqual([]);
    expect(
      check(stubProvider, [{ path: "src/app.ts", text: "export {};" }]),
    ).toEqual([]);
  });
});
