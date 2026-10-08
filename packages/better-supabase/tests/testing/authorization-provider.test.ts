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
    ).toContainEqual(expect.stringMatching(/scope "team" has id type numeric/));
    expect(await failures(withProvider({ tenantScope: "workspace" }))).toEqual([
      expect.stringMatching(/tenantScope "workspace" is not in scopes/),
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
});
