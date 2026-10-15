import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.teams.options`. */
export type TeamsSqlOptions = {
  readonly teamIdType?: unknown;
};

export const teamsSqlOptions: BlockOptionsSchema<TeamsSqlOptions> =
  blockOptions<TeamsSqlOptions>({
    teamIdType: option.unknown(),
  });
