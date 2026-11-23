import type { AuthorizationProvider } from "./authorization.ts";
import type { AnyBlocksConfig } from "./blocks.ts";

import { tokenizeTemplate } from "../core/sql-template-tokens.ts";
import { DEFAULT_ACTIVE_TENANT } from "./blocks.ts";

/** Why a config entry equals what the render would use without it. */
export type RestatedKind =
  | "identity"
  | "null"
  | "empty"
  | "tenant"
  | "default"
  | "permission"
  | "option"
  | "hook"
  | "table"
  | "column"
  | "api"
  | "binding"
  | "recordType"
  | "provider"
  | "notNull";

/** One config entry the resolved defaults already supply. */
export interface RestatedEntry {
  readonly kind: RestatedKind;
  /** The key path in the config, as `blocks.<name>.columns.<table>.<column>`. */
  readonly path: string;
  readonly reason: string;
  /** The value the entry resolves to either way. */
  readonly value: unknown;
}

/** What `restatedEntries` reads besides the config. */
export interface RestatedInput {
  readonly blocks: AnyBlocksConfig;
  readonly sqlTenantColumn?: string | undefined;
  /** `ResolvedConfig.restatedDefaults`: `api` and `audit` equal to `sql`'s. */
  readonly restatedDefaults?: readonly {
    readonly block: string;
    readonly key: "api" | "audit";
  }[];
  /** The authorization provider, when the app uses the provider model. */
  readonly provider?: AuthorizationProvider | undefined;
  /** `subjects`, for permission keys the provider's `actionKeys` repeat. */
  readonly subjects?: Readonly<
    Record<
      string,
      { readonly permissions?: Readonly<Record<string, unknown>> | undefined }
    >
  >;
  /** The default column names of a module's tables, by logical table. */
  readonly defaultColumns: (
    module: string,
  ) =>
    | Readonly<
        Record<
          string,
          {
            readonly columns: Readonly<Record<string, string>>;
            readonly optional?: readonly string[];
          }
        >
      >
    | undefined;
  /** `gen.functions`, for `notNull` entries a block already declares. */
  readonly genFunctions?: Readonly<
    Record<string, { readonly notNull?: unknown } | undefined>
  >;
  /** What an installed block declares as not null for a function name. */
  readonly blockNotNull?: (name: string) => unknown;
  /** The `null` entries for columns the app's views lack anyway. */
  readonly nulls?: readonly {
    readonly block: string;
    readonly logical: string;
    readonly column: string;
    readonly name: string;
    readonly view: string;
  }[];
}

/** The keys whose string values are SQL templates, compared token by token. */
const TEMPLATE_KEYS: ReadonlySet<string> = new Set([
  "where",
  "canAssign",
  "canAssignFor",
  "function",
]);

/**
 * A SQL template as its tokens: whitespace is dropped, and unquoted words and
 * function names fold to lower case as Postgres does. Strings, quoted
 * identifiers and placeholders keep their text.
 */
function templateForm(template: string): readonly string[] {
  return tokenizeTemplate(template).flatMap((token) => {
    switch (token.kind) {
      case "space": {
        return [];
      }

      case "word": {
        return [token.quoted ? token.text : token.text.toLowerCase()];
      }

      case "string":
      case "placeholder":
      case "punct":
      case "comment":
      case "dollar":
      case "error": {
        return [`${token.kind}:${token.text}`];
      }

      default: {
        return token satisfies never;
      }
    }
  });
}

/**
 * A value in the form two configs resolve to the same render with: object keys
 * sorted, undefined entries dropped, `active` values sorted, and SQL templates
 * as tokens. A `status` without it has no `active` list to compare. A column
 * string (`schema.table.column`, a user or tenant that counts as disabled when
 * the column is set) stays apart from an active row (`{ table, id, disabledAt
 * }`): a missing row disables there, so they render differently.
 */
function resolved(value: unknown, key?: string): unknown {
  if (typeof value === "string") {
    return key !== undefined && TEMPLATE_KEYS.has(key)
      ? { template: templateForm(value) }
      : value;
  }

  if (Array.isArray(value)) {
    const items = value.map((item) => resolved(item));

    return key === "active"
      ? items.toSorted((a, b) => String(a).localeCompare(String(b)))
      : items;
  }

  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, entry]) => entry !== undefined)
        .toSorted(([a], [b]) => a.localeCompare(b))
        .map(([name, entry]) => [name, resolved(entry, name)]),
    );
  }

  return value;
}

/** Whether two config values resolve to the same thing (ADR 1174). */
const same = (a: unknown, b: unknown): boolean =>
  JSON.stringify(resolved(a)) === JSON.stringify(resolved(b));

/**
 * The config entries that equal their resolved default, so removing each one
 * changes nothing in the render: an identity column mapping on an optional
 * column, a `null` for a column the view lacks, an empty map, a tenant column
 * equal to `sql.tenantColumn`, and a value equal to the provider's.
 */
export function restatedEntries(input: RestatedInput): RestatedEntry[] {
  const found: RestatedEntry[] = [];

  for (const [name, entry] of Object.entries(input.blocks)) {
    if (entry === undefined) {
      continue;
    }

    const tables = input.defaultColumns(entry.block ?? name);
    const prefix = `blocks.${name}`;

    for (const key of ["columns", "values", "tables"] as const) {
      const map = entry[key];

      if (map !== undefined && Object.keys(map).length === 0) {
        found.push({
          kind: "empty",
          path: `${prefix}.${key}`,
          reason: "is empty",
          value: {},
        });
      }
    }

    for (const [table, columns] of Object.entries(entry.columns ?? {})) {
      if (columns === undefined) {
        continue;
      }

      if (Object.keys(columns).length === 0) {
        found.push({
          kind: "empty",
          path: `${prefix}.columns.${table}`,
          reason: "is empty",
          value: {},
        });
      }

      for (const [logical, mapped] of Object.entries(columns)) {
        const path = `${prefix}.columns.${table}.${logical}`;

        if (
          logical === "tenant" &&
          typeof mapped === "string" &&
          mapped === input.sqlTenantColumn
        ) {
          found.push({
            kind: "tenant",
            path,
            reason: `repeats sql.tenantColumn "${mapped}"`,
            value: mapped,
          });

          continue;
        }

        const spec = tables?.[table];

        const required = entry.requiredColumns?.[table]?.includes(logical);

        if (
          typeof mapped === "string" &&
          spec?.optional?.includes(logical) === true &&
          spec.columns[logical] === mapped &&
          required !== true
        ) {
          found.push({
            kind: "identity",
            path,
            reason: `names the default column "${mapped}" of an optional column. Write { column: "${mapped}", required: true } to require it, or remove the entry`,
            value: mapped,
          });
        }
      }
    }
  }

  for (const entry of input.restatedDefaults ?? []) {
    found.push({
      kind: "default",
      path: `blocks.${entry.block}.${entry.key}`,
      reason: `repeats sql.${entry.key}`,
      value: entry.key,
    });
  }

  if (input.blocks.permissions?.activeTenant === DEFAULT_ACTIVE_TENANT) {
    found.push({
      kind: "default",
      path: "blocks.permissions.activeTenant",
      reason: `repeats the default "resolver" (the tenant the request resolved). The provider's tokenHook.activeOrganizationFrom is compared by BS409, not by this entry`,
      value: DEFAULT_ACTIVE_TENANT,
    });
  }

  for (const entry of input.nulls ?? []) {
    found.push({
      kind: "null",
      path: `blocks.${entry.block}.columns.${entry.logical}.${entry.column}`,
      reason: `maps to null, but ${entry.view} has no "${entry.name}" column`,
      value: null,
    });
  }

  for (const [key, spec] of Object.entries(input.genFunctions ?? {})) {
    const declared = input.blockNotNull?.(key.slice(key.lastIndexOf(".") + 1));

    if (
      spec?.notNull !== undefined &&
      declared !== undefined &&
      same(spec.notNull, declared)
    ) {
      found.push({
        kind: "notNull",
        path: `gen.functions.${key}.notNull`,
        reason: "repeats the not-null result the block declares for it",
        value: declared,
      });
    }
  }

  const provided = providerEntries(input);
  const paths = new Set(provided.map((entry) => entry.path));

  return [...found.filter((entry) => !paths.has(entry.path)), ...provided];
}

function providerEntries(input: RestatedInput): RestatedEntry[] {
  const provider = input.provider;

  if (provider === undefined) {
    return [];
  }

  const out: RestatedEntry[] = [];
  const label = `the authorization provider "${provider.name}"`;

  const add = (path: string, what: string, value: unknown): void => {
    out.push({
      kind: "provider",
      path,
      reason: `repeats ${what} of ${label}`,
      value,
    });
  };

  const keys = provider.actionKeys;

  for (const [name, actions] of Object.entries(keys?.blocks ?? {})) {
    const set = input.blocks[name]?.permissions;

    for (const [action, key] of Object.entries(actions)) {
      if (set?.[action] === key) {
        add(`blocks.${name}.permissions.${action}`, "an actionKeys entry", key);
      }
    }
  }

  for (const [type, actions] of Object.entries(keys?.recordTypes ?? {})) {
    const set = input.subjects?.[type]?.permissions;

    for (const [action, key] of Object.entries(actions)) {
      if (set?.[action] === key) {
        add(
          `subjects.${type}.permissions.${action}`,
          "an actionKeys entry",
          key,
        );
      }
    }
  }

  const invitations = input.blocks["invitations"];
  const memberships = input.blocks["memberships"];
  const platformRoles = invitations?.options?.["platformRoles"];

  if (
    platformRoles !== undefined &&
    provider.platformRoles !== undefined &&
    same(platformRoles, provider.platformRoles)
  ) {
    add(
      "blocks.invitations.options.platformRoles",
      "platformRoles",
      platformRoles,
    );
  }

  const through = memberships?.options?.["roleThrough"];

  if (
    through !== undefined &&
    (provider.roleSources ?? []).some((source) =>
      same(source.role.through, through),
    )
  ) {
    add("blocks.memberships.options.roleThrough", "a role source", through);
  }

  const disabledAt = memberships?.columns?.["memberships"]?.["disabledAt"];

  if (
    typeof disabledAt === "string" &&
    (provider.memberships ?? []).some(
      (entry) => entry.disabledAt === disabledAt,
    )
  ) {
    add(
      "blocks.memberships.columns.memberships.disabledAt",
      "the disabledAt",
      disabledAt,
    );
  }

  const disabled = input.blocks.permissions?.disabled;

  if (disabled !== undefined && provider.suspension !== undefined) {
    for (const key of ["tenant", "user"] as const) {
      if (
        disabled[key] !== undefined &&
        provider.suspension[key] !== undefined &&
        same(disabled[key], provider.suspension[key])
      ) {
        add(
          `blocks.permissions.disabled.${key}`,
          `the suspension.${key}`,
          disabled[key],
        );
      }
    }

    const providerUser =
      disabled.user === undefined ||
      (provider.suspension.user !== undefined &&
        same(disabled.user, provider.suspension.user));

    if (
      providerUser &&
      disabled.userKey !== undefined &&
      provider.suspension.userKey !== undefined &&
      same(disabled.userKey, provider.suspension.userKey)
    ) {
      add(
        "blocks.permissions.disabled.userKey",
        "the suspension.userKey",
        disabled.userKey,
      );
    }
  }

  const claimsHook = input.blocks["impersonation"]?.options?.["claimsHook"];

  if (
    claimsHook !== undefined &&
    provider.tokenHook?.function !== undefined &&
    same({ function: claimsHook }, { function: provider.tokenHook.function })
  ) {
    add(
      "blocks.impersonation.options.claimsHook",
      "the tokenHook.function",
      claimsHook,
    );
  }

  return out;
}
