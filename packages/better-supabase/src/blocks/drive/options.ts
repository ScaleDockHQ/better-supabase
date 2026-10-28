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

export type DriveRoleFunctions = {
  readonly node?: DriveRoleHook;
  readonly drive?: DriveRoleHook;
};

/** `blocks.drive.options`. */
export type DriveSqlOptions = {
  readonly roles?: readonly string[];
  readonly writeRole?: unknown;
  readonly shareRole?: unknown;
  readonly memberRole?: unknown;
  readonly subjectType?: string;
  readonly conflict?: string;
  readonly drives?: boolean;
  readonly driveKinds?: readonly string[];
  readonly sources?: readonly string[];
  readonly roleFunctions?: DriveRoleFunctions;
  readonly readPolicy?: boolean;
  readonly extraColumns?: ExtraColumns;
};

export const driveSqlOptions: BlockOptionsSchema<DriveSqlOptions> =
  blockOptions<DriveSqlOptions>({
    roles: option.strings({ default: ["viewer", "editor", "owner"] }),
    writeRole: option.unknown(),
    shareRole: option.unknown(),
    memberRole: option.unknown(),
    subjectType: option.string({ default: "drive_node" }),
    conflict: option.string({ default: "fail" }),
    drives: option.boolean({ default: false }),
    driveKinds: option.strings({ default: ["shared"] }),
    sources: option.strings({ default: ["google-drive", "onedrive"] }),
    roleFunctions: option.unknown<DriveRoleFunctions>(),
    readPolicy: option.boolean({ default: true }),
    extraColumns: option.extraColumns(),
  });
