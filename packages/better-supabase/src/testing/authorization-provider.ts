import type { AuthorizationProvider } from "../config/authorization.ts";
import type { DisabledRow } from "../config/blocks.ts";
import type { Check, ConformanceReport } from "./conformance.ts";

import {
  isScopeName,
  scopeProblems,
  TEMPLATE_PLACEHOLDERS,
  templateFunctions,
  templatePlaceholders,
  templateProblems,
} from "../core/access-sql.ts";
import { authzUserTopic } from "../core/authz-topic.ts";
import { AUTHZ_VERSION_CLAIM, PERMISSIONS_CLAIM } from "../core/claim-names.ts";
import { conform, expect } from "./conformance.ts";
import { hasName } from "./kits/executor.ts";

function isPlainJson(value: unknown): boolean {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    return true;
  }

  if (typeof value === "number") {
    return Number.isFinite(value);
  }

  if (Array.isArray(value)) {
    return value.every(isPlainJson);
  }

  if (typeof value !== "object") {
    return false;
  }

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

  for (const column of [row.disabledAt, row.status]) {
    if (column !== undefined) {
      expect(
        IDENTIFIER.test(column),
        `${where} column "${column}" is not a column`,
      );
    }
  }

  expect(
    (row.status === undefined) === (row.active === undefined),
    `${where} needs status and active together`,
  );
}

/** One query runner, as `createPostgres()` returns it. */
interface ProviderSqlClient {
  queryRaw<R = Record<string, unknown>>(
    text: string,
    params?: unknown[],
  ): Promise<R[]>;
}

/**
 * The database the provider's SQL is installed in: `createPostgres()` from
 * `better-supabase/postgres` fits.
 */
export interface ProviderPostgres {
  readonly admin: ProviderSqlClient;
  asUser(claims: {
    readonly sub: string;
    readonly role: string;
  }): ProviderSqlClient;
}

export interface AuthorizationProviderKitOptions {
  /**
   * Runs the checks that need the provider's SQL: the `versions` function's
   * signature, that a user can't read another user's version, and the Realtime
   * policy for `authz:<uid>`.
   */
  readonly postgres?: ProviderPostgres;
}

const VERSION_FUNCTION = /^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$/;

/**
 * Proves an `AuthorizationProvider` targets API v1, is plain JSON, names valid
 * scopes with a tenant scope that has an id type, writes templates that are
 * safe to inline and use the placeholders they need, lists every function its
 * templates call in `requires`, and keeps its token hook, suspension rows, role
 * sources and deciding columns well formed. A hook that writes `permissions`
 * (owned or registered) needs a key marked `sqlComplete`, and one truncated
 * marker when its budget can cut the claim. A provider that keeps the
 * authorization versions names a `schema.function` and, when it has a token
 * hook, writes `authz_ver` from it; with `options.postgres` the kit also checks
 * that function and the Realtime policy in the database.
 */
export function testAuthorizationProvider(
  provider: AuthorizationProvider,
  options: AuthorizationProviderKitOptions = {},
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

          for (const placeholder of templatePlaceholders(template)) {
            expect(
              allowed.includes(placeholder),
              `functions.${name} uses {${placeholder}}; it takes ${allowed.map((key) => `{${key}}`).join(", ")}`,
            );
          }

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

          for (const key of needed) {
            expect(
              template.includes(`{${key}}`),
              key === "scope"
                ? `functions.${name} doesn't use {scope}, so it answers the same for every scope`
                : `functions.${name} doesn't use {${key}}`,
            );
          }
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

        for (const entry of provider.requires ?? []) {
          expect(
            QUALIFIED.test(entry.function),
            `requires "${entry.function}" is not schema.name`,
          );
        }

        for (const [name, template] of templates) {
          for (const scope of template.includes("{scope}")
            ? scopes
            : [undefined]) {
            for (const fn of templateFunctions(template, scope)) {
              expect(
                required.has(fn),
                `functions.${name} calls ${fn}, which requires doesn't list`,
              );
            }
          }
        }
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

          for (const scope of permission.scopes ?? []) {
            expect(
              scopes.has(scope),
              `permission "${permission.key}" names unknown scope "${scope}"`,
            );
          }
        }
      },
    ],
    provider.operations && [
      "operations name listed permissions",
      () => {
        const keys =
          provider.permissions === undefined
            ? undefined
            : new Set(provider.permissions.map((entry) => entry.key));

        for (const [name, operation] of Object.entries(provider.operations!)) {
          expect(name !== "", "an operation name is empty");
          expect(
            operation.permission !== "",
            `operation "${name}" names no permission`,
          );

          if (keys) {
            expect(
              keys.has(operation.permission),
              `operation "${name}" needs "${operation.permission}", which permissions doesn't list`,
            );
          }
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

          if ("value" in membership.scope) {
            expect(
              scopes.has(membership.scope.value),
              `${membership.table} names unknown scope "${membership.scope.value}"`,
            );
          }
        }
      },
    ],
    provider.suspension && [
      "suspension rows name a table, an id and a state column",
      () => {
        const { user, tenant } = provider.suspension!;

        if (user) {
          expectRow("suspension.user", user);
        }

        if (tenant) {
          expectRow("suspension.tenant", tenant);
        }
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
          ]) {
            expect(
              IDENTIFIER.test(column),
              `roleSources ${source.table} names "${column}", which is not a column`,
            );
          }
        }
      },
    ],
    provider.decidingColumns && [
      "deciding columns are schema.table.column",
      () => {
        for (const column of provider.decidingColumns!) {
          expect(
            COLUMN.test(column),
            `decidingColumns "${column}" is not schema.table.column`,
          );
        }
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

          for (const claim of hook.budget.claims) {
            expect(
              written.has(claim),
              `tokenHook.budget counts "${claim}", which neither ownedClaims nor registeredClaims lists`,
            );
          }
        }
      },
    ],
    provider.tokenHook && [
      "names one truncated marker, apart from the claims it marks",
      () => {
        const hook = provider.tokenHook!;

        const markers = [
          hook.truncatedClaim,
          hook.budget?.truncatedClaim,
        ].filter((marker) => marker !== undefined);

        for (const marker of markers) {
          expect(
            IDENTIFIER.test(marker),
            `truncated marker "${marker}" is not a claim name`,
          );
          expect(
            marker !== PERMISSIONS_CLAIM &&
              !(hook.budget?.claims ?? []).includes(marker),
            `truncated marker "${marker}" is also a claim it marks`,
          );
        }

        expect(
          new Set(markers).size <= 1,
          `tokenHook.truncatedClaim "${hook.truncatedClaim}" and budget.truncatedClaim "${hook.budget?.truncatedClaim}" disagree: readers and doctor would look at different markers`,
        );

        const capped =
          (hook.budget?.claims ?? []).includes(PERMISSIONS_CLAIM) &&
          (hook.ownedClaims.includes(PERMISSIONS_CLAIM) ||
            (hook.registeredClaims ?? []).some(
              (claim) => claim.name === PERMISSIONS_CLAIM,
            ));

        expect(
          !capped || markers.length > 0,
          `tokenHook.budget can drop "${PERMISSIONS_CLAIM}" entries, so it needs truncatedClaim: readers would take a cut claim as complete`,
        );
      },
    ],
    provider.tokenHook && [
      `writes "${PERMISSIONS_CLAIM}" only with keys complete in SQL`,
      () => {
        const hook = provider.tokenHook!;
        const owned = hook.ownedClaims.includes(PERMISSIONS_CLAIM);

        const registered = (hook.registeredClaims ?? []).some(
          (claim) => claim.name === PERMISSIONS_CLAIM,
        );

        if (!owned && !registered) {
          return;
        }

        expect(
          (provider.permissions ?? []).some((entry) => entry.sqlComplete),
          `tokenHook writes "${PERMISSIONS_CLAIM}", but permissions marks no key sqlComplete: the claim only carries those keys, so it would always be empty`,
        );
      },
    ],
    ...versionChecks(provider, options.postgres),
  ]);
}

const AUTHZ_TOPIC_PREFIX = authzUserTopic("");

function versionChecks(
  provider: AuthorizationProvider,
  postgres: ProviderPostgres | undefined,
): Check[] {
  const versions = provider.versions;

  if (!versions) {
    return [];
  }

  const fn = versions.function;
  const [schema = "", name = ""] = fn.split(".");

  const checks: Check[] = [
    [
      "names its versions function as schema.function",
      () => {
        expect(
          VERSION_FUNCTION.test(fn),
          `versions.function "${fn}" is not a lower-case schema.function`,
        );
      },
    ],
    [
      `writes "${AUTHZ_VERSION_CLAIM}" from its versions`,
      () => {
        const hook = provider.tokenHook;

        if (!hook) {
          return;
        }

        expect(
          hook.ownedClaims.includes(AUTHZ_VERSION_CLAIM) ||
            (hook.registeredClaims ?? []).some(
              (claim) => claim.name === AUTHZ_VERSION_CLAIM,
            ),
          `versions names ${fn}, but tokenHook neither owns nor registers "${AUTHZ_VERSION_CLAIM}": tokens would carry no version to compare`,
        );
      },
    ],
  ];

  if (!postgres) {
    return checks;
  }

  return [
    ...checks,
    [
      "its versions function takes a uuid and returns bigint",
      async () => {
        const rows = await postgres.admin.queryRaw<{ returns: string }>(
          `select format_type(p.prorettype, null) as returns
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = $1 and p.proname = $2
             and pg_get_function_identity_arguments(p.oid) ~ '^([a-z_]+ )?uuid$'`,
          [schema, name],
        );

        expect(rows.length === 1, `${fn}(uuid) does not exist`);
        expect(
          rows[0]?.returns === "bigint",
          `${fn}(uuid) returns ${rows[0]?.returns ?? "nothing"}, not bigint`,
        );
      },
    ],
    [
      "a user can't read another user's version",
      async () => {
        const caller = crypto.randomUUID();
        let read: unknown;

        try {
          const rows = await postgres
            .asUser({ sub: caller, role: "authenticated" })
            .queryRaw<{ version: unknown }>(
              `select ${schema}.${name}($1::uuid) as version`,
              [crypto.randomUUID()],
            );

          read = rows[0]?.version ?? null;
        } catch {
          read = null;
        }

        expect(
          read === null,
          `an authenticated user read another user's version from ${fn}: close it to client roles, or return null for anyone but auth.uid()`,
        );
      },
    ],
    [
      `a Realtime policy lets users receive ${AUTHZ_TOPIC_PREFIX}<uid>`,
      async () => {
        const rows = await postgres.admin.queryRaw<{ name: string }>(
          `select policyname as name from pg_policies
           where schemaname = 'realtime' and tablename = 'messages'
             and cmd in ('SELECT', 'ALL')
             and coalesce(qual, '') like $1`,
          [`%${AUTHZ_TOPIC_PREFIX}%`],
        );

        expect(
          rows.length > 0,
          `no policy on realtime.messages mentions "${AUTHZ_TOPIC_PREFIX}": clients can't receive the version broadcast`,
        );
      },
    ],
  ];
}
