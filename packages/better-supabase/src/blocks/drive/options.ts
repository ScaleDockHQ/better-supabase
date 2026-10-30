import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * App functions that decide the caller's role on a node or a drive:
 * `schema.name(id uuid, user uuid)` returns one of `options.roles`, or null.
 * With one set, the block calls it instead of its own grants for that level.
 */
export type DriveRoleHook =
  | string
  | { readonly rows: string; readonly roles: Readonly<Record<string, string>> };

/** `blocks.drive.options.quota`: the usage meter uploads count against. */
export type DriveQuota = { readonly meter: string };

/**
 * `blocks.drive.options.control`: files saved as controlled documents get a
 * number, a type, an owner, a release workflow through approvals and periodic
 * reviews. Needs the numbering, versions, approvals and state-machine blocks.
 */
export type DriveControl = {
  /** The document types, such as `sop` or `policy`. */
  readonly types: readonly string[];
  /** The months between reviews when a document sets none; 12 by default. */
  readonly reviewMonths?: number;
  /** The role that makes a document obsolete; the share role by default. */
  readonly releaseRole?: string;
};

export type DriveRoleFunctions = {
  readonly node?: DriveRoleHook;
  readonly drive?: DriveRoleHook;
};

/** `blocks.drive.options`. */
export type DriveSqlOptions = {
  readonly roles?: readonly string[];
  readonly writeRole?: unknown;
  readonly shareRole?: unknown;
  readonly commentRole?: unknown;
  readonly memberRole?: unknown;
  readonly uploadRole?: unknown;
  readonly subjectType?: string;
  readonly conflict?: string;
  readonly drives?: boolean;
  readonly driveKinds?: readonly string[];
  readonly sources?: readonly string[];
  readonly roleFunctions?: DriveRoleFunctions;
  readonly readPolicy?: boolean;
  readonly previewPrefix?: string;
  readonly extraColumns?: ExtraColumns;
  readonly maxTextBytes?: number;
  readonly quota?: DriveQuota;
  readonly control?: DriveControl;
};

export const driveSqlOptions: BlockOptionsSchema<DriveSqlOptions> =
  blockOptions<DriveSqlOptions>({
    roles: option.strings({ default: ["viewer", "editor", "owner"] }),
    writeRole: option.unknown(),
    shareRole: option.unknown(),
    commentRole: option.unknown(),
    memberRole: option.unknown(),
    uploadRole: option.unknown(),
    subjectType: option.string({ default: "drive_node" }),
    conflict: option.string({ default: "fail" }),
    drives: option.boolean({ default: false }),
    driveKinds: option.strings({ default: ["shared"] }),
    sources: option.strings({ default: ["google-drive", "onedrive"] }),
    roleFunctions: option.unknown<DriveRoleFunctions>(),
    readPolicy: option.boolean({ default: true }),
    previewPrefix: option.string({ default: "_previews" }),
    extraColumns: option.extraColumns(),
    maxTextBytes: option.number({ default: 1_048_576 }),
    quota: option.unknown<DriveQuota>(),
    control: option.unknown<DriveControl>(),
  });
