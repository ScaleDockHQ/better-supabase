import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.assets.options`. */
export type AssetsSqlOptions = {
  /**
   * Store points and areas as PostGIS geography (ADR 0066). Installs the
   * `postgis` extension. Default `false`: latitude and longitude only, with
   * haversine distances and no areas.
   */
  readonly postgis?: boolean;
};

export const assetsSqlOptions: BlockOptionsSchema<AssetsSqlOptions> =
  blockOptions<AssetsSqlOptions>({
    postgis: option.boolean({ default: false }),
  });
