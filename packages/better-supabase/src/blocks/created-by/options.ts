import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * `blocks["created-by"].options`: the columns `createdByExtension` fills on
 * every table that has them.
 */
export type CreatedBySqlOptions = {
  readonly createdBy?: string;
  readonly updatedBy?: string;
  /** The admin behind an impersonated write; `track_actor` fills it. */
  readonly impersonatedBy?: string;
  readonly stamp?: "client" | "server";
};

export const createdBySqlOptions: BlockOptionsSchema<CreatedBySqlOptions> =
  blockOptions<CreatedBySqlOptions>({
    createdBy: option.string({ default: "created_by" }),
    updatedBy: option.string({ default: "updated_by" }),
    impersonatedBy: option.string({ default: "impersonated_by" }),
    stamp: option.unknown<"client" | "server">({ default: "client" }),
  });
