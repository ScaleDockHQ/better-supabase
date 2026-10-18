/**
 * The column types an app table may use. Money is a `bigint` of minor units
 * next to a `text` currency column (ADR 0024 and 0037), never `numeric`.
 */
export const APP_COLUMN_TYPES = [
  "text",
  "uuid",
  "integer",
  "bigint",
  "numeric",
  "boolean",
  "timestamptz",
  "date",
  "jsonb",
  "text[]",
] as const;

export type AppColumnType = (typeof APP_COLUMN_TYPES)[number];

/**
 * What a column references: another app table, `auth.users`
 * (`{ table: "auth.users" }`), or a logical table of an installed block
 * (`{ block: "crm", table: "contacts" }`), which follows the block's
 * renames.
 */
export type AppReferenceTarget =
  | { readonly table: string }
  | { readonly block: string; readonly table: string };

export type AppReference = AppReferenceTarget & {
  /** Defaults to `no action`. */
  readonly onDelete?: "cascade" | "restrict" | "set null" | "no action";
};

export interface AppColumnConfig {
  readonly type: AppColumnType;
  /** Defaults to true. */
  readonly nullable?: boolean;
  /**
   * The column default, from an allowlist: `now()`, `gen_random_uuid()`,
   * `auth.uid()`, `true`, `false`, a number, a `'quoted'` text literal,
   * and `'{}'` or `'[]'` for `jsonb` and `text[]`.
   */
  readonly default?: string;
  readonly unique?: boolean;
  readonly references?: AppReference;
}

/**
 * A table the app owns, created in `public` by `better-supabase sql sync`
 * next to the block files. Every table gets `id`, the scope column and
 * (unless `timestamps: false`) `created_at` and `updated_at`.
 */
export interface AppTableConfig {
  /** The table's own columns, keyed by lower snake name. */
  readonly columns?: Readonly<Record<string, AppColumnConfig>>;
  /**
   * Who reaches a row. `inherit` (the default) follows `sql.scope`: per
   * tenant, members of the row's tenant; per user, the row's user. `user`
   * keeps rows per user in any scope, and `none` lets signed-in users read
   * every row while only the service role writes.
   */
  readonly scope?: "inherit" | "user" | "none";
  /** `created_at` and `updated_at`. Defaults to true. */
  readonly timestamps?: boolean;
}

export type AppTablesConfig = Readonly<Record<string, AppTableConfig>>;
