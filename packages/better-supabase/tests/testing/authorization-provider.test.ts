import { describe, expect, it } from "vitest";

import type { AuthorizationProvider } from "../../src/config/index.ts";

import { testAuthorizationProvider } from "../../src/testing/authorization-provider.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import {
  stubProvider,
  withProvider,
} from "../fixtures/authorization-provider.ts";

async function failures(provider: AuthorizationProvider): Promise<string[]> {
  const error = await testAuthorizationProvider(provider).then(
    () => undefined,
    (cause: unknown) => cause,
  );
  expect(error).toBeInstanceOf(ConformanceError);
  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => `${check.name}: ${check.message ?? ""}`);
}

describe("testAuthorizationProvider", () => {
  it("passes a provider that follows the contract", async () => {
    const report = await testAuthorizationProvider(stubProvider);
    expect(report.subject).toBe('AuthorizationProvider "stub"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks.map((check) => check.name)).toContain(
      "requires every function the templates call",
    );
  });

  it("refuses another API version and values that aren't JSON", async () => {
    expect(
      await failures({
        ...stubProvider,
        // @ts-expect-error -- the kit checks providers written in JavaScript too.
        apiVersion: 2,
      }),
    ).toEqual(["targets authorization API v1: apiVersion is 2"]);
    expect(
      await failures({
        ...stubProvider,
        name: "stub",
        // @ts-expect-error -- a function is not plain data.
        problems: [() => "x"],
      }),
    ).toEqual(["is plain JSON: it doesn't survive a JSON round trip"]);
  });

  it("refuses bad scopes", async () => {
    expect(
      await failures(
        withProvider({ scopes: [{ name: "Org", idType: "uuid" }] }),
      ),
    ).toContainEqual(
      expect.stringMatching(/scope "Org" is not lower snake case/),
    );
    expect(
      await failures(
        withProvider({
          scopes: [
            { name: "organization", idType: "uuid" },
            { name: "team", idType: "numeric", parent: "workspace" },
          ],
        }),
      ),
    ).toContainEqual(
      expect.stringMatching(
        /scope "team" has idType "numeric".*scope "team" has parent "workspace", which is not a scope/,
      ),
    );
    expect(await failures(withProvider({ tenantScope: "workspace" }))).toEqual([
      expect.stringMatching(/tenantScope "workspace" is not a scope/),
    ]);
    expect(
      await failures(
        withProvider({
          scopes: [
            { name: "organization", parent: "project" },
            { name: "project", idType: "uuid", parent: "organization" },
          ],
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /is its own ancestor \(a parent cycle\).*tenant scope "organization" has no idType/,
      ),
    ]);
  });

  it("refuses placeholders a template doesn't take, or a missing one", async () => {
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            isPlatform: "authz.is_platform({permission}, {tenant})",
            idsWithFor: "authz.ids_{scope}_for({permission})",
          },
        }),
      ),
    ).toEqual([expect.stringMatching(/functions\.isPlatform uses \{tenant\}/)]);
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            idsWithFor: "authz.ids_{scope}_for({permission})",
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/functions\.idsWithFor doesn't use \{user\}/),
    ]);
  });

  it("refuses a template that calls a function requires doesn't list", async () => {
    expect(
      await failures(
        withProvider({
          requires: stubProvider.requires.filter(
            (entry) => entry.function !== "authz.ids_project",
          ),
        }),
      ),
    ).toEqual([
      expect.stringMatching(/functions\.idsWith calls authz\.ids_project/),
    ]);
  });

  it("refuses repeated permissions and unknown scopes", async () => {
    expect(
      await failures(
        withProvider({
          permissions: [
            { key: "documents.read", sqlComplete: true },
            { key: "documents.read", sqlComplete: true, scopes: ["team"] },
          ],
          memberships: [
            {
              table: "authz.team_members",
              userColumn: "user_id",
              scope: { value: "team" },
              idColumn: "team_id",
            },
          ],
          tokenHook: {
            ...stubProvider.tokenHook,
            function: "access_token_hook",
            budget: { claims: ["memberships"], bytes: 0 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/permission "documents\.read" repeats/),
      expect.stringMatching(/authz\.team_members names unknown scope "team"/),
      expect.stringMatching(
        /tokenHook\.function "access_token_hook" is not schema\.name/,
      ),
    ]);
  });

  it("needs {scope}, {tenant} and {role} where the template must tell them apart", async () => {
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            idsWith: "authz.ids_organization({permission})",
            canAssign: "authz.can_assign({tenant}, 'member')",
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /functions\.idsWith doesn't use \{scope\}, so it answers the same for every scope/,
      ),
    ]);
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            canAssign: "authz.can_assign({role})",
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/functions\.canAssign doesn't use \{tenant\}/),
    ]);
  });

  it("refuses templates that aren't safe to inline", async () => {
    for (const [template, problem] of [
      ["authz.ids_{scope}({permission}); drop table x", /contains ";"/],
      ["authz.ids_{scope}({permission}) -- x", /contains "--"/],
      ["$$authz.ids_{scope}({permission})$$", /contains "\$\$"/],
      ["ids_{scope}({permission})", /calls ids_scope\(\) without a schema/],
      [
        "array(select unnest(authz.ids_{scope}({permission})))",
        /calls unnest\(\) without a schema/,
      ],
    ] as const) {
      expect(
        await failures(
          withProvider({
            functions: { ...stubProvider.functions, idsWith: template },
          }),
        ),
      ).toContainEqual(expect.stringMatching(problem));
    }
    expect(
      await testAuthorizationProvider(
        withProvider({
          functions: {
            ...stubProvider.functions,
            idsWith: "authz.ids_{scope}(coalesce({permission}, ';'))",
          },
        }),
      ),
    ).toBeDefined();
  });

  it("needs requires when the templates call functions", async () => {
    expect(await failures(withProvider({ requires: undefined }))).toEqual([
      expect.stringMatching(
        /the templates call functions, but requires is unset/,
      ),
    ]);
  });

  it("keeps owned and registered token hook claims apart", async () => {
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            ownedClaims: ["memberships", "features"],
            budget: { claims: ["features"], bytes: 512 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /tokenHook registers "features", which ownedClaims also lists/,
      ),
    ]);
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            budget: { claims: ["permissions"], bytes: 512 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/tokenHook\.budget counts "permissions"/),
    ]);
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            budget: { claims: ["features"], bytes: 512.5 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /tokenHook\.budget\.bytes must be a positive integer/,
      ),
    ]);
    expect(
      await failures(
        withProvider({
          tokenHook: { ...stubProvider.tokenHook, ownedClaims: [] },
        }),
      ),
    ).toEqual([expect.stringMatching(/tokenHook\.ownedClaims is empty/)]);
  });

  it("checks suspension rows, role sources and deciding columns", async () => {
    expect(
      await failures(
        withProvider({
          suspension: {
            user: { table: "users", id: "id", disabledAt: "disabled_at" },
            tenant: { table: "authz.orgs", id: "id", status: "status" },
          },
          roleSources: [
            {
              table: "authz.memberships",
              role: {
                column: "role_id",
                through: { table: "roles", id: "id", column: "name" },
              },
            },
          ],
          decidingColumns: ["authz.memberships"],
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /suspension\.user\.table "users" is not schema\.table/,
      ),
      expect.stringMatching(
        /roleSources authz\.memberships reads roles from "roles"/,
      ),
      expect.stringMatching(
        /decidingColumns "authz\.memberships" is not schema\.table\.column/,
      ),
    ]);
  });

  it("accepts permissionsFor and canApprove", async () => {
    const report = await testAuthorizationProvider(
      withProvider({
        functions: {
          ...stubProvider.functions,
          permissionsFor: "authz.permissions_for({user}, {tenant})",
          canApprove: "authz.can_approve({tenant}, {tool})",
        },
        requires: [
          ...stubProvider.requires,
          {
            function: "authz.permissions_for",
            args: "uuid, uuid",
            role: "authenticated",
          },
          {
            function: "authz.can_approve",
            args: "uuid, text",
            role: "authenticated",
          },
        ],
        approvals: { distinctApprover: true },
      }),
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });
});
