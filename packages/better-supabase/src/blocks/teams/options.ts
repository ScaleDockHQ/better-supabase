import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.teams.options`. */
export type TeamsSqlOptions = {
  readonly teamIdType?: unknown;
  readonly extraColumns?: unknown;
};

export const teamsSqlOptions: BlockOptionsSchema<TeamsSqlOptions> =
  blockOptions<TeamsSqlOptions>({
    teamIdType: option.unknown(),
    extraColumns: option.unknown(),
  });
