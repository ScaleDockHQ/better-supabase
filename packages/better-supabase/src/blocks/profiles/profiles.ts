import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  isRecord,
} from "../shared.ts";

export interface ProfilesOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `sql.modules.profiles.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** Error mappers that run before the built-in ones, as in `betterSupabase.mapError()`. */
  readonly mappers?: readonly ErrorMapper[];
}

/** The caller's profile columns, by database name. */
export type Profile = Readonly<Record<string, unknown>>;

export interface Profiles {
  mine(): AsyncResult<Profile | undefined>;
  updateMine(attrs: Readonly<Record<string, unknown>>): AsyncResult<boolean>;
}

/**
 * The `profiles` SQL module as typed calls. `mine` and `updateMine` are the
 * functions a signed-in user runs on their own row.
 */
export function createProfiles(options: ProfilesOptions): Profiles {
  applyTemporal(options);
  const run = blockCall(
    options.transport,
    options.schema,
    options.mappers ?? [],
  );

  return {
    mine() {
      return run("my_profile", {}, (value) =>
        value === null || value === undefined
          ? undefined
          : isRecord(value)
            ? value
            : undefined,
      );
    },
    updateMine(attrs) {
      return run("update_my_profile", { attrs }, (value) => value === true);
    },
  };
}
