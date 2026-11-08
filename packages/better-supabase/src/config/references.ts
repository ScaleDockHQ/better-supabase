import type { BlockNameRegistry, TablesOf } from "../blocks/name-registry.ts";
import type { AuthorizationProvider } from "./authorization.ts";
import type { BlockConfigOf, BlockName, InstanceOn } from "./blocks.ts";
import type { BlockInput } from "./types/groups.ts";

/**
 * A logical table of a block the registry knows, as a column reference names
 * it: `{ block: "tasks", table: "items" }`.
 */
export type BlockTableReference = {
  readonly [M in keyof BlockNameRegistry]: {
    readonly block: M;
    readonly table: TablesOf<M>;
  };
}[keyof BlockNameRegistry];

type RolesOf<C> = C extends {
  readonly blocks: {
    readonly permissions: { readonly roles: infer R extends object };
  };
}
  ? keyof R & string
  : never;

/**
 * The roles `blocks.permissions.roles` declares, or `string` when the config
 * leaves them to the default list or another access model.
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

type BlocksOf<C> = C extends { readonly blocks: infer B extends object }
  ? B extends readonly string[]
    ? Record<never, never>
    : B
  : Record<never, never>;

/** The instance keys a literal config declares in `blocks`. */
export type InstanceNames<C> = keyof BlocksOf<C> & string;

/**
 * Each named instance checked against the block it names in `block`, and every
 * `uses` value against the config's instances.
 */
type InstanceReferences<C> = {
  readonly blocks?: {
    readonly [K in keyof BlocksOf<C>]?: (BlocksOf<C>[K] extends {
      readonly block: infer B extends BlockName;
    }
      ? BlockInput<BlockConfigOf<B>>
      : unknown) & {
      readonly on?: InstanceOn;
      readonly uses?: Readonly<Record<string, InstanceNames<C>>>;
    };
  };
};

type ProviderOf<C> = C extends {
  readonly auth: { readonly authorization: infer P };
}
  ? P
  : never;

/**
 * The permission keys a typed provider (`AuthorizationProvider<Key>`) declares,
 * or `string` when the config has no provider or an untyped one.
 */
export type ProviderKeys<C> = [ProviderOf<C>] extends [never]
  ? string
  : ProviderOf<C> extends AuthorizationProvider<infer K>
    ? K
    : string;

type PermissionReferences<C> =
  string extends ProviderKeys<C>
    ? unknown
    : {
        readonly blocks?: {
          readonly [K in keyof BlocksOf<C>]?: {
            readonly [field: string]: unknown;
            readonly permissions?: Readonly<Record<string, ProviderKeys<C>>>;
            readonly roles?: Readonly<
              Record<string, readonly ("*" | ProviderKeys<C>)[]>
            >;
            readonly scopes?: Readonly<
              Record<string, readonly ProviderKeys<C>[]>
            >;
          };
        };
        readonly recordTypes?: Readonly<
          Record<
            string,
            {
              readonly [field: string]: unknown;
              readonly permissions?: Readonly<
                Record<
                  string,
                  | ProviderKeys<C>
                  | {
                      readonly key?: ProviderKeys<C>;
                      readonly also?: ProviderKeys<C>;
                    }
                >
              >;
            }
          >
        >;
      };

/**
 * What `defineConfig` checks a literal config against: bucket names in
 * `gen.storagePaths`, the role names other blocks take from
 * `blocks.permissions.roles`, and each named instance's options and `uses`.
 */
export type ConfigReferences<C> = {
  readonly gen?: {
    readonly storagePaths?: Readonly<Record<string, BucketName<C>>>;
  };
} & RoleReferences<C> &
  PermissionReferences<C> &
  InstanceReferences<C>;
