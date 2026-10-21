import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.profiles.options`. */
export type ProfilesSqlOptions = {
  readonly columnGrants?: boolean;
  readonly extraColumns?: unknown;
  readonly metadata?: unknown;
  readonly mirrorEmail?: boolean;
  readonly readPolicy?: unknown;
  readonly reservedUsernames?: readonly string[];
  readonly serviceColumns?: readonly string[];
  readonly splitName?: boolean;
  readonly syncTrigger?: boolean;
  readonly updatable?: readonly string[];
  readonly username?: boolean;
  readonly usernameFrom?: unknown;
  readonly usernameMaxLength?: number;
  readonly usernameMinLength?: number;
};

export const profilesSqlOptions: BlockOptionsSchema<ProfilesSqlOptions> =
  blockOptions<ProfilesSqlOptions>({
    columnGrants: option.boolean(),
    extraColumns: option.unknown(),
    metadata: option.unknown(),
    mirrorEmail: option.boolean({ default: true }),
    readPolicy: option.unknown(),
    reservedUsernames: option.strings(),
    serviceColumns: option.strings(),
    splitName: option.boolean({ default: true }),
    syncTrigger: option.boolean({ default: true }),
    updatable: option.strings(),
    username: option.boolean({ default: true }),
    usernameFrom: option.unknown(),
    usernameMaxLength: option.number({ default: 32 }),
    usernameMinLength: option.number({ default: 3 }),
  });
