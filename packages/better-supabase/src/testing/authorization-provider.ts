import type { AuthorizationProvider } from "../config/authorization.ts";
import type { DisabledRow } from "../config/modules.ts";

import {
  isScopeName,
  scopeProblems,
  TEMPLATE_PLACEHOLDERS,
  templateFunctions,
  templatePlaceholders,
  templateProblems,
} from "../core/access-sql.ts";
import {
  type ConformanceReport,
  conform,
  expect,
  hasName,
} from "./conformance.ts";

function isPlainJson(value: unknown): boolean {
  if (value === null || typeof value === "string" || typeof value === "boolean")
    return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(isPlainJson);
  if (typeof value !== "object") return false;
  const prototype: unknown = Object.getPrototypeOf(value);
  return (
    (prototype === Object.prototype || prototype === null) &&
    Object.values(value).every(
      (entry) => entry === undefined || isPlainJson(entry),
    )
  );
}

const QUALIFIED = /^[a-z_][\w$]*\.[a-z_][\w${}]*$/i;
const TABLE = /^[a-z_][\w$]*\.[a-z_][\w$]*$/i;
const COLUMN = /^[a-z_][\w$]*\.[a-z_][\w$]*\.[a-z_][\w$]*$/i;
const IDENTIFIER = /^[a-z_][\w$]*$/i;

function expectRow(where: string, row: DisabledRow): void {
  expect(
    TABLE.test(row.table),
    `${where}.table "${row.table}" is not schema.table`,
  );
  expect(IDENTIFIER.test(row.id), `${where}.id "${row.id}" is not a column`);
  expect(
    row.disabledAt !== undefined || row.status !== undefined,
    `${where} sets neither disabledAt nor status`,
  );
  for (const column of [row.disabledAt, row.status])
    if (column !== undefined)
      expect(
        IDENTIFIER.test(column),
        `${where} column "${column}" is not a column`,
      );
  expect(
    (row.status === undefined) === (row.active === undefined),
    `${where} needs status and active together`,
  );
}

/**
 * Proves an `AuthorizationProvider` targets API v1, is plain JSON, names
 * valid scopes with a tenant scope that has an id type, writes templates
 * that are safe to inline and use the placeholders they need, lists every
 * function its templates call in `requires`, and keeps its token hook,
 * suspension rows, role sources and deciding columns well formed.
 */
export function testAuthorizationProvider(
  provider: AuthorizationProvider,
): Promise<ConformanceReport> {
  const scopes = new Set(provider.scopes.map((scope) => scope.name));
  const templates = Object.entries(provider.functions).filter(
    (entry): entry is [keyof typeof TEMPLATE_PLACEHOLDERS, string] =>
      typeof entry[1] === "string",
  );
  const calls = templates.some(([, template]) =>
    (template.includes("{scope}") ? [...scopes] : [undefined]).some(
      (scope) => templateFunctions(template, scope).length > 0,
    ),
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
        expect(isPlainJson(provider), "it doesn't survive a JSON round trip");
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
        }
        const problems = scopeProblems(provider);
        expect(problems.length === 0, problems.join("; "));
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
          const needed = allowed.filter(
            (key) =>
              key === "permission" ||
              key === "user" ||
              key === "tenant" ||
              key === "role" ||
              (key === "scope" &&
                scopes.size > 1 &&
                name.startsWith("idsWith")),
          );
          for (const key of needed)
            expect(
              template.includes(`{${key}}`),
              key === "scope"
                ? `functions.${name} doesn't use {scope}, so it answers the same for every scope`
                : `functions.${name} doesn't use {${key}}`,
            );
        }
      },
    ],
    [
      "templates are safe to inline",
      () => {
        for (const [name, template] of templates) {
          const problems = templateProblems(template);
          expect(
            problems.length === 0,
            `functions.${name} ${problems.join(", ")}`,
          );
        }
      },
    ],
    [
      "requires every function the templates call",
      () => {
        expect(
          !calls || provider.requires !== undefined,
          "the templates call functions, but requires is unset",
        );
        const required = new Set(
          (provider.requires ?? []).map((entry) => entry.function),
        );
        for (const entry of provider.requires ?? [])
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
        for (const membership of provider.memberships!) {
          expect(
            TABLE.test(membership.table),
            `membership table "${membership.table}" is not schema.table`,
          );
          if ("value" in membership.scope)
            expect(
              scopes.has(membership.scope.value),
              `${membership.table} names unknown scope "${membership.scope.value}"`,
            );
        }
      },
    ],
    provider.suspension && [
      "suspension rows name a table, an id and a state column",
      () => {
        const { user, tenant } = provider.suspension!;
        if (user) expectRow("suspension.user", user);
        if (tenant) expectRow("suspension.tenant", tenant);
      },
    ],
    provider.roleSources && [
      "role sources name schema.table and columns",
      () => {
        for (const source of provider.roleSources!) {
          expect(
            TABLE.test(source.table),
            `roleSources table "${source.table}" is not schema.table`,
          );
          expect(
            TABLE.test(source.role.through.table),
            `roleSources ${source.table} reads roles from "${source.role.through.table}", which is not schema.table`,
          );
          for (const column of [
            source.role.column,
            source.role.through.id,
            source.role.through.column,
          ])
            expect(
              IDENTIFIER.test(column),
              `roleSources ${source.table} names "${column}", which is not a column`,
            );
        }
      },
    ],
    provider.decidingColumns && [
      "deciding columns are schema.table.column",
      () => {
        for (const column of provider.decidingColumns!)
          expect(
            COLUMN.test(column),
            `decidingColumns "${column}" is not schema.table.column`,
          );
      },
    ],
    provider.tokenHook && [
      "names its token hook and the claims it writes",
      () => {
        const hook = provider.tokenHook!;
        expect(
          QUALIFIED.test(hook.function),
          `tokenHook.function "${hook.function}" is not schema.name`,
        );
        expect(hook.ownedClaims.length > 0, "tokenHook.ownedClaims is empty");
        const owned = new Set(hook.ownedClaims);
        const written = new Set(owned);
        for (const claim of hook.registeredClaims ?? []) {
          expect(
            QUALIFIED.test(claim.function),
            `tokenHook claim "${claim.name}" calls "${claim.function}", which is not schema.name`,
          );
          expect(
            !owned.has(claim.name),
            `tokenHook registers "${claim.name}", which ownedClaims also lists: a claim the hook owns has no second writer`,
          );
          written.add(claim.name);
        }
        if (hook.budget !== undefined) {
          expect(
            Number.isInteger(hook.budget.bytes) && hook.budget.bytes > 0,
            "tokenHook.budget.bytes must be a positive integer",
          );
          for (const claim of hook.budget.claims)
            expect(
              written.has(claim),
              `tokenHook.budget counts "${claim}", which neither ownedClaims nor registeredClaims lists`,
            );
        }
      },
    ],
  ]);
}
