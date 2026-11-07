import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * `roleThrough`: memberships store a role id, and `table.column` holds the role
 * name it points at.
 */
export interface RoleThroughOption {
  /** `schema.table` of the roles. */
  readonly table: string;
  /** The key column the membership's role points at. */
  readonly id: string;
  /** The role name column. */
  readonly column: string;
  /** The tenant column of tenant custom roles, null for shared roles. */
  readonly tenant?: string;
  /** A condition on the roles row `{row}` that holds for tenant roles only. */
  readonly where?: string;
}

/** One table whose foreign key must stay inside the row's tenant. */
export interface SameTenantEntry {
  /** `schema.table` that holds the foreign key. */
  readonly table: string;
  readonly column: string;
  /** The referenced `schema.table`, or the table and its key and tenant columns. */
  readonly references:
    | string
    | {
        readonly table: string;
        readonly column?: string;
        readonly tenant?: string;
        /** A condition on the referenced row `{row}`. */
        readonly where?: string;
      };
  /** The tenant column of `table`. Default the memberships tenant column. */
  readonly tenant?: string;
  /** More columns that must match: `{ <column>: "<referenced column>" }`. */
  readonly match?: Readonly<Record<string, string>>;
  /** The tables a dotted `match` key reads through. */
  readonly through?: Readonly<
    Record<
      string,
      string | { readonly table: string; readonly column?: string }
    >
  >;
}

/**
 * `sameTenant`: exceptions and extra entries on top of the keys the schema
 * files declare (every foreign key between two tenant tables is checked by
 * default), `false` to check none, or `{ auto: false, entries }` for the listed
 * entries alone.
 */
export type SameTenantOption =
  | false
  | readonly SameTenantEntry[]
  | { readonly auto: boolean; readonly entries?: readonly SameTenantEntry[] };

/** `blocks.memberships.options`. */
export type MembershipsSqlOptions = {
  readonly claimFormat?: string;
  readonly roleThrough?: RoleThroughOption;
  readonly sameTenant?: SameTenantOption;
  /** `{ many: true }` lets a member hold several roles (`membership_roles`). */
  readonly roles?: { readonly many?: boolean };
};

export const membershipsSqlOptions: BlockOptionsSchema<MembershipsSqlOptions> =
  blockOptions<MembershipsSqlOptions>({
    claimFormat: option.string({ default: "array" }),
    roleThrough: option.unknown<RoleThroughOption>(),
    sameTenant: option.unknown<SameTenantOption>(),
    roles: option.unknown<{ readonly many?: boolean }>(),
  });
