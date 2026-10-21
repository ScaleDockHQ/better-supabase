import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.drive.options`. */
export type DriveSqlOptions = {
  readonly roles?: readonly string[];
  readonly writeRole?: unknown;
  readonly shareRole?: unknown;
  readonly memberRole?: unknown;
  readonly subjectType?: string;
  readonly conflict?: string;
  readonly extraColumns?: unknown;
};

export const driveSqlOptions: BlockOptionsSchema<DriveSqlOptions> =
  blockOptions<DriveSqlOptions>({
    roles: option.strings({ default: ["viewer", "editor", "owner"] }),
    writeRole: option.unknown(),
    shareRole: option.unknown(),
    memberRole: option.unknown(),
    subjectType: option.string({ default: "drive_node" }),
    conflict: option.string({ default: "fail" }),
    extraColumns: option.unknown(),
  });
