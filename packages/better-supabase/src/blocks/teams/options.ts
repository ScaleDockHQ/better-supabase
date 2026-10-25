import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.teams.options`. */
export type TeamsSqlOptions = {
  /** The key type of teams. Default `uuid`; `inbox` needs `uuid`. */
  readonly teamIdType?: "uuid" | "bigint";
  readonly extraColumns?: ExtraColumns;
};

export const teamsSqlOptions: BlockOptionsSchema<TeamsSqlOptions> =
  blockOptions<TeamsSqlOptions>({
    teamIdType: option.string<"uuid" | "bigint">({ default: "uuid" }),
    extraColumns: option.extraColumns(),
  });
