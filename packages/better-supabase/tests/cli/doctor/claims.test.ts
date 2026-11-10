import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";
import type { AuthorizationProvider } from "../../../src/config/index.ts";

import { AUTHORIZATION_RULES } from "../../../src/cli/doctor/authorization.ts";
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

describe("BS426", () => {
  it("reports config values equal to the provider's", () => {
    const platformRoles = {
      table: "app.platform_roles",
      user: "user_id",
      role: "role",
    };

    const provider: AuthorizationProvider = { ...stubProvider, platformRoles };

    const config = resolveConfig(
      {
        auth: { authorization: provider },
        blocks: {
          permissions: { model: "provider" },
          invitations: { options: { platformRoles } },
        },
      },
      "/project",
    );

    const rule = AUTHORIZATION_RULES.find((entry) => entry.code === "BS426");

    // SAFETY: BS426 reads only `config`.
    const found = rule?.check({ config } as unknown as DoctorContext);

    expect(rule?.severity).toBe("info");
    expect(found).toEqual([
      expect.objectContaining({
        target: "blocks.invitations.options.platformRoles",
      }),
    ]);
  });

  it("reports roleThrough and disabledAt values equal to the provider's", async () => {
    const through = { table: "app.roles", id: "id", column: "name" };

    const provider: AuthorizationProvider = {
      ...stubProvider,
      roleSources: [
        { table: "app.members", role: { column: "role_id", through } },
      ],
      memberships: [
        {
          table: "app.members",
          userColumn: "user_id",
          scope: { column: "org_id" },
          idColumn: "id",
          disabledAt: "disabled_at",
        },
      ],
    };

    const config = resolveConfig(
      {
        auth: { authorization: provider },
        blocks: {
          permissions: { model: "provider" },
          memberships: {
            options: { roleThrough: through },
            columns: { memberships: { disabledAt: "disabled_at" } },
          },
        },
      },
      "/project",
    );

    const rule = AUTHORIZATION_RULES.find((entry) => entry.code === "BS426");

    // SAFETY: BS426 reads only `config`.
    const found = rule?.check({ config } as unknown as DoctorContext);

    expect((await found)?.map((finding) => finding.target)).toEqual([
      "blocks.memberships.options.roleThrough",
      "blocks.memberships.columns.memberships.disabledAt",
    ]);
  });

  it("reports a disabled setting equal to the provider's suspension", async () => {
    const user = { table: "app.profiles", id: "id", disabledAt: "banned_at" };

    const provider: AuthorizationProvider = {
      ...stubProvider,
      suspension: { user, userKey: "user_id" },
    };

    const config = resolveConfig(
      {
        auth: { authorization: provider },
        blocks: {
          permissions: {
            model: "provider",
            disabled: { user, userKey: "user_id" },
          },
        },
      },
      "/project",
    );

    const rule = AUTHORIZATION_RULES.find((entry) => entry.code === "BS426");

    // SAFETY: BS426 reads only `config`.
    const found = rule?.check({ config } as unknown as DoctorContext);

    expect((await found)?.map((finding) => finding.target)).toEqual([
      "blocks.permissions.disabled.user",
      "blocks.permissions.disabled.userKey",
    ]);
  });

  it("says nothing when the access model is not the provider", () => {
    const platformRoles = {
      table: "app.platform_roles",
      user: "user_id",
      role: "role",
    };

    const config = resolveConfig(
      {
        auth: { authorization: { ...stubProvider, platformRoles } },
        blocks: {
          permissions: { model: "roles" },
          invitations: { options: { platformRoles } },
        },
      },
      "/project",
    );

    const rule = AUTHORIZATION_RULES.find((entry) => entry.code === "BS426");

    // SAFETY: BS426 reads only `config`.
    const found = rule?.check({ config } as unknown as DoctorContext);

    expect(found).toEqual([]);
  });

  it("keeps userKey when the config sets its own user column", async () => {
    const provider: AuthorizationProvider = {
      ...stubProvider,
      suspension: {
        user: { table: "app.profiles", id: "id", disabledAt: "banned_at" },
        userKey: "user_id",
      },
    };

    const config = resolveConfig(
      {
        auth: { authorization: provider },
        blocks: {
          permissions: {
            model: "provider",
            disabled: {
              user: "public.accounts.disabled_at",
              userKey: "user_id",
            },
          },
        },
      },
      "/project",
    );

    const rule = AUTHORIZATION_RULES.find((entry) => entry.code === "BS426");

    // SAFETY: BS426 reads only `config`.
    const found = rule?.check({ config } as unknown as DoctorContext);

    expect((await found)?.map((finding) => finding.target)).toEqual([]);
  });
});
