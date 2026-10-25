import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * `blocks["updated-at"].options`: the columns `updatedAtExtension` treats as
 * managed on every table that has them.
 */
export type UpdatedAtSqlOptions = {
  readonly createdAt?: string;
  readonly updatedAt?: string;
  readonly stamp?: "client" | "server";
};

export const updatedAtSqlOptions: BlockOptionsSchema<UpdatedAtSqlOptions> =
  blockOptions<UpdatedAtSqlOptions>({
    createdAt: option.string({ default: "created_at" }),
    updatedAt: option.string({ default: "updated_at" }),
    stamp: option.unknown<"client" | "server">({ default: "client" }),
  });
