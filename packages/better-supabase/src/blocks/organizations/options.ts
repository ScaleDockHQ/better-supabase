import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.organizations.options`. */
export type OrganizationsSqlOptions = {
  readonly assignmentGuard?: string;
  readonly attributes?: readonly string[];
  readonly auditCategory?: unknown;
  readonly deleteMode?: string;
  readonly extraColumns?: ExtraColumns;
  readonly formerOwnerRole?: string;
  readonly ownerInvariant?: boolean;
  readonly ownerRole?: string;
  readonly reservedSlugs?: readonly string[];
  readonly slugCitext?: boolean;
  readonly slugMaxLength?: number;
  readonly slugMinLength?: number;
  readonly slugPattern?: string;
};

export const organizationsSqlOptions: BlockOptionsSchema<OrganizationsSqlOptions> =
  blockOptions<OrganizationsSqlOptions>({
    assignmentGuard: option.string({ default: "module" }),
    attributes: option.strings({ default: [] }),
    auditCategory: option.unknown(),
    deleteMode: option.string({ default: "hard" }),
    extraColumns: option.extraColumns(),
    formerOwnerRole: option.string({ default: "admin" }),
    ownerInvariant: option.boolean({ default: true }),
    ownerRole: option.string({ default: "owner" }),
    reservedSlugs: option.strings({ default: [] }),
    slugCitext: option.boolean({ default: false }),
    slugMaxLength: option.number({ default: 48 }),
    slugMinLength: option.number({ default: 2 }),
    slugPattern: option.string(),
  });

/**
 * `platformRoles`: the platform roles a provider keeps outside the tenant,
 * which an invitation can grant.
 */
export interface PlatformRolesOption {
  /** `schema.table` of the platform role grants. */
  readonly table: string;
  /** The user column. */
  readonly user: string;
  /** The role column. */
  readonly role: string;
  /** Where the role name lives when `role` holds an id. */
  readonly through?: {
    readonly table: string;
    readonly id: string;
    readonly column: string;
    /** A condition on the roles row `{row}`. */
    readonly where?: string;
  };
  /** A SQL template that holds when the caller may grant `{role}`. */
  readonly canAssign?: string;
  /** The same check for another user, `{user}`. */
  readonly canAssignFor?: string;
}

/** `blocks.invitations.options`. */
export type InvitationsSqlOptions = {
  readonly maxValidFor?: string;
  readonly platformRoles?: PlatformRolesOption;
  readonly prefill?: boolean;
  readonly previewColumns?: readonly string[];
  readonly requireConfirmedEmail?: boolean;
  readonly tokenBytes?: number;
  readonly tokenStorage?: string;
  readonly validFor?: string;
  readonly extraColumns?: ExtraColumns;
  /** The role `create_invitation` and `invite_member` use when none is named. */
  readonly defaultRole?: string;
  /** Extra roles and teams an invitation grants on accept. */
  readonly onAccept?: { readonly roles?: boolean; readonly teams?: boolean };
};

export const invitationsSqlOptions: BlockOptionsSchema<InvitationsSqlOptions> =
  blockOptions<InvitationsSqlOptions>({
    maxValidFor: option.string({ default: "30 days" }),
    platformRoles: option.unknown<PlatformRolesOption>(),
    prefill: option.boolean({ default: false }),
    previewColumns: option.strings({ default: ["name"] }),
    requireConfirmedEmail: option.boolean({ default: true }),
    tokenBytes: option.number({ default: 24 }),
    tokenStorage: option.string({ default: "sha256" }),
    validFor: option.string({ default: "7 days" }),
    extraColumns: option.extraColumns(),
    defaultRole: option.string({ default: "member" }),
    onAccept: option.unknown<{
      readonly roles?: boolean;
      readonly teams?: boolean;
    }>(),
  });
