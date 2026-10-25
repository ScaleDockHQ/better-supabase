import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.teams.options`. */
export type TeamsSqlOptions = {
  /** The key type of teams. Default `uuid`; `inbox` needs `uuid`. */
  readonly teamIdType?: "uuid" | "bigint";
  readonly extraColumns?: ExtraColumns;
  /**
   * `create_team` takes the caller's `slug`, and `update_team` a `patch` that
   * sets `name`, `slug` and `description` and can clear the description.
   */
  readonly patch?: boolean;
  /** Writes `restore_team`, which makes an archived team active again. */
  readonly restore?: boolean;
};

export const teamsSqlOptions: BlockOptionsSchema<TeamsSqlOptions> =
  blockOptions<TeamsSqlOptions>({
    teamIdType: option.string<"uuid" | "bigint">({ default: "uuid" }),
    extraColumns: option.extraColumns(),
    patch: option.boolean({ default: false }),
    restore: option.boolean({ default: false }),
  });
