import type { AuthorizationProvider } from "../config/authorization.ts";

import {
  isScopeName,
  TEMPLATE_PLACEHOLDERS,
  templateFunctions,
  templatePlaceholders,
} from "../core/access-sql.ts";
import {
  type ConformanceReport,
  conform,
  expect,
  hasName,
  same,
} from "./conformance.ts";

const ID_TYPES: ReadonlySet<string> = new Set([
  "uuid",
  "text",
  "bigint",
  "integer",
]);
const QUALIFIED = /^[a-z_][\w$]*\.[a-z_][\w${}]*$/i;

/**
 * Proves an `AuthorizationProvider` targets API v1, is plain JSON, names
 * valid scopes, uses only the placeholders each template takes, and lists
 * every function its templates call in `requires`.
 */
export function testAuthorizationProvider(
  provider: AuthorizationProvider,
): Promise<ConformanceReport> {
  const scopes = new Set(provider.scopes.map((scope) => scope.name));
  const templates = Object.entries(provider.functions).filter(
    (entry): entry is [keyof typeof TEMPLATE_PLACEHOLDERS, string] =>
      typeof entry[1] === "string",
  );
  return conform(`AuthorizationProvider "${provider.name}"`, [
    hasName(provider),
    [
      "targets authorization API v1",
      () => {
        expect(
          // oxlint-disable-next-line typescript/no-unnecessary-condition -- the kit checks providers written in JavaScript too.
          provider.apiVersion === 1,
          `apiVersion is ${String(provider.apiVersion)}`,
        );
      },
    ],
    [
      "is plain JSON",
      () => {
        expect(
          same(JSON.parse(JSON.stringify(provider)), provider),
          "it doesn't survive a JSON round trip",
        );
      },
    ],
    [
      "names valid, unique scopes",
      () => {
        expect(scopes.size > 0, "scopes is empty");
        expect(scopes.size === provider.scopes.length, "a scope name repeats");
        for (const scope of provider.scopes) {
          expect(
            isScopeName(scope.name),
            `scope "${scope.name}" is not lower snake case`,
          );
          expect(
            scope.idType === undefined || ID_TYPES.has(scope.idType),
            `scope "${scope.name}" has id type ${String(scope.idType)}`,
          );
          expect(
            scope.parent === undefined || scopes.has(scope.parent),
            `scope "${scope.name}" sits in unknown scope "${String(scope.parent)}"`,
          );
        }
        expect(
          scopes.has(provider.tenantScope),
          `tenantScope "${provider.tenantScope}" is not in scopes`,
        );
      },
    ],
    [
      "templates use only their placeholders",
      () => {
        for (const [name, template] of templates) {
          const allowed: readonly string[] | undefined =
            TEMPLATE_PLACEHOLDERS[name];
          expect(allowed, `functions.${name} is not a known template`);
          for (const placeholder of templatePlaceholders(template))
            expect(
              allowed.includes(placeholder),
              `functions.${name} uses {${placeholder}}; it takes ${allowed.map((key) => `{${key}}`).join(", ")}`,
            );
          if (allowed.includes("permission"))
            expect(
              template.includes("{permission}"),
              `functions.${name} doesn't use {permission}`,
            );
          if (allowed.includes("user"))
            expect(
              template.includes("{user}"),
              `functions.${name} doesn't use {user}`,
            );
        }
      },
    ],
    provider.requires && [
      "requires every function the templates call",
      () => {
        const required = new Set(
          provider.requires!.map((entry) => entry.function),
        );
        for (const entry of provider.requires!)
          expect(
            QUALIFIED.test(entry.function),
            `requires "${entry.function}" is not schema.name`,
          );
        for (const [name, template] of templates)
          for (const scope of template.includes("{scope}")
            ? scopes
            : [undefined])
            for (const fn of templateFunctions(template, scope))
              expect(
                required.has(fn),
                `functions.${name} calls ${fn}, which requires doesn't list`,
              );
      },
    ],
    provider.permissions && [
      "lists each permission once, at known scopes",
      () => {
        const keys = new Set<string>();
        for (const permission of provider.permissions!) {
          expect(permission.key !== "", "a permission key is empty");
          expect(
            !keys.has(permission.key),
            `permission "${permission.key}" repeats`,
          );
          keys.add(permission.key);
          for (const scope of permission.scopes ?? [])
            expect(
              scopes.has(scope),
              `permission "${permission.key}" names unknown scope "${scope}"`,
            );
        }
      },
    ],
    provider.memberships && [
      "memberships name known scopes",
      () => {
        for (const membership of provider.memberships!)
          if ("value" in membership.scope)
            expect(
              scopes.has(membership.scope.value),
              `${membership.table} names unknown scope "${membership.scope.value}"`,
            );
      },
    ],
    provider.tokenHook && [
      "names its token hook",
      () => {
        const hook = provider.tokenHook!;
        expect(
          QUALIFIED.test(hook.function),
          `tokenHook.function "${hook.function}" is not schema.name`,
        );
        for (const claim of hook.registeredClaims ?? [])
          expect(
            QUALIFIED.test(claim.function),
            `tokenHook claim "${claim.name}" calls "${claim.function}", which is not schema.name`,
          );
        expect(
          hook.budget === undefined ||
            (Number.isInteger(hook.budget.bytes) && hook.budget.bytes > 0),
          "tokenHook.budget.bytes must be a positive integer",
        );
      },
    ],
  ]);
}
