import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.guests.options.representation`. */
export interface GuestRepresentationOptions {
  /**
   * The subject types a representative reaches as a guest: a guest whose party
   * is a contacts person that `represents` a record of one of these types reads
   * it, and comments and uploads with `authority: "act"`.
   */
  readonly subjects: readonly string[];
}

/** `blocks.guests.options`. */
export type GuestsSqlOptions = {
  readonly representation?: GuestRepresentationOptions;
};

export const guestsSqlOptions: BlockOptionsSchema<GuestsSqlOptions> =
  blockOptions<GuestsSqlOptions>({
    representation: option.unknown<GuestRepresentationOptions>(),
  });
