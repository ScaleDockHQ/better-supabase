import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.organizations.options`. */
export type OrganizationsSqlOptions = {
  readonly assignmentGuard?: string;
  readonly attributes?: readonly string[];
  readonly auditCategory?: unknown;
  readonly deleteMode?: string;
  readonly extraColumns?: unknown;
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
    extraColumns: option.unknown(),
    formerOwnerRole: option.string({ default: "admin" }),
    ownerInvariant: option.boolean({ default: true }),
    ownerRole: option.string({ default: "owner" }),
    reservedSlugs: option.strings({ default: [] }),
    slugCitext: option.boolean({ default: false }),
    slugMaxLength: option.number({ default: 48 }),
    slugMinLength: option.number({ default: 2 }),
    slugPattern: option.string(),
  });

/** `blocks.invitations.options`. */
export type InvitationsSqlOptions = {
  readonly maxValidFor?: string;
  readonly platformRoles?: unknown;
  readonly prefill?: boolean;
  readonly previewColumns?: readonly string[];
  readonly requireConfirmedEmail?: boolean;
  readonly tokenBytes?: number;
  readonly tokenStorage?: string;
  readonly validFor?: string;
  readonly extraColumns?: unknown;
};

export const invitationsSqlOptions: BlockOptionsSchema<InvitationsSqlOptions> =
  blockOptions<InvitationsSqlOptions>({
    maxValidFor: option.string({ default: "30 days" }),
    platformRoles: option.unknown(),
    prefill: option.boolean({ default: false }),
    previewColumns: option.strings({ default: ["name"] }),
    requireConfirmedEmail: option.boolean({ default: true }),
    tokenBytes: option.number({ default: 24 }),
    tokenStorage: option.string({ default: "sha256" }),
    validFor: option.string({ default: "7 days" }),
    extraColumns: option.unknown(),
  });
