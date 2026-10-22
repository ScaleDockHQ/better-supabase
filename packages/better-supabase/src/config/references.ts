import type { BlockNameRegistry, TablesOf } from "../blocks/name-registry.ts";
import type { AppOnDeleteAction } from "./types/app-tables.ts";

/**
 * A logical table of a block the registry knows, as `tables` columns reference
 * it: `{ block: "work-items", table: "items" }`.
 */
export type BlockTableReference = {
  readonly [M in keyof BlockNameRegistry]: {
    readonly block: M;
    readonly table: TablesOf<M>;
  };
}[keyof BlockNameRegistry];

type AppTablesOf<C> = C extends { readonly tables: infer T extends object }
  ? T
  : Record<never, never>;

/** The app tables a literal config declares, or `string` without any. */
export type AppTableNames<C> = [keyof AppTablesOf<C>] extends [never]
  ? string
  : (keyof AppTablesOf<C> & string) | "auth.users";

/** What a column of `C`'s app tables may reference. */
export type TypedReference<C> = (
  | { readonly table: AppTableNames<C> }
  | BlockTableReference
) & { readonly onDelete?: AppOnDeleteAction };

type ColumnsOfTable<T> = T extends { readonly columns: infer K extends object }
  ? K
  : Record<never, never>;

type AppTableReferences<C> = {
  readonly [T in keyof AppTablesOf<C>]?: {
    readonly columns?: {
      readonly [K in keyof ColumnsOfTable<AppTablesOf<C>[T]>]?: ColumnsOfTable<
        AppTablesOf<C>[T]
      >[K] extends { readonly references: unknown }
        ? { readonly references?: TypedReference<C> }
        : unknown;
    };
  };
};

type RolesOf<C> = C extends {
  readonly blocks: {
    readonly access: { readonly roles: infer R extends object };
  };
}
  ? keyof R & string
  : never;

/**
 * The roles `blocks.access.roles` declares, or `string` when the config leaves
 * them to the default list or another access model.
 */
export type RoleNames<C> = [RolesOf<C>] extends [never] ? string : RolesOf<C>;

type BucketsOf<C> = C extends {
  readonly database: { readonly buckets: infer B extends object };
}
  ? keyof B & string
  : never;

/**
 * A bucket `gen.storagePaths` names: a `database.buckets` key, suggested first,
 * or the id of a bucket the config doesn't declare.
 */
export type BucketName<C> = BucketsOf<C> | (string & {});

type RoleReferences<C> = [RolesOf<C>] extends [never]
  ? unknown
  : {
      readonly blocks?: {
        readonly sso?: {
          readonly options?: {
            readonly defaultRole?: RoleNames<C>;
            readonly roleOrder?: readonly RoleNames<C>[];
          };
        };
        readonly billing?: {
          readonly options?: { readonly seatRoles?: readonly RoleNames<C>[] };
        };
      };
    };

/**
 * What `defineConfig` checks a literal config against: block tables in `tables`
 * references, app table names, bucket names in `gen.storagePaths`, and the role
 * names other blocks take from `blocks.access.roles`.
 */
export type ConfigReferences<C> = {
  readonly tables?: AppTableReferences<C>;
  readonly gen?: {
    readonly storagePaths?: Readonly<Record<string, BucketName<C>>>;
  };
} & RoleReferences<C>;
