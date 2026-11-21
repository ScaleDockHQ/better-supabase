import type { AuthorizationProvider } from "./authorization.ts";
import type { AnyBlocksConfig } from "./blocks.ts";

/** Why a config entry equals what the render would use without it. */
export type RestatedKind =
  | "identity"
  | "null"
  | "empty"
  | "tenant"
  | "default"
  | "permission"
  | "option"
  | "provider";

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
  /** The `null` entries for columns the app's views lack anyway. */
  readonly nulls?: readonly {
    readonly block: string;
    readonly logical: string;
    readonly column: string;
    readonly name: string;
    readonly view: string;
  }[];
}

const same = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a) === JSON.stringify(b);

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

  for (const entry of input.nulls ?? []) {
    found.push({
      kind: "null",
      path: `blocks.${entry.block}.columns.${entry.logical}.${entry.column}`,
      reason: `maps to null, but ${entry.view} has no "${entry.name}" column`,
      value: null,
    });
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
    claimsHook === provider.tokenHook.function
  ) {
    add(
      "blocks.impersonation.options.claimsHook",
      "the tokenHook.function",
      claimsHook,
    );
  }

  return out;
}
