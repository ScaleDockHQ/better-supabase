import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { rawError } from "../../core/block-transport.ts";
import { mapDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import {
  applyTemporal,
  type BlockTemporalOptions,
  isRecord,
} from "../shared.ts";

export interface ProfilesOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `sql.modules.profiles.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  readonly errorMappers?: readonly ErrorMapper[];
}

/** The caller's profile columns, by database name. */
export type Profile = Readonly<Record<string, unknown>>;

export interface Profiles {
  mine(): AsyncResult<Profile | undefined>;
  updateMine(attrs: Readonly<Record<string, unknown>>): AsyncResult<boolean>;
}

const DEFAULT_SCHEMA = "better_supabase";

/**
 * The `profiles` SQL module as typed calls. `mine` and `updateMine` are the
 * functions a signed-in user runs on their own row.
 */
export function createProfiles(options: ProfilesOptions): Profiles {
  applyTemporal(options);
  const schema = options.schema ?? DEFAULT_SCHEMA;
  const mappers = options.errorMappers ?? [];

  function run<T>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T,
  ): AsyncResult<T> {
    return AsyncResult.from(async () => {
      let value: unknown;
      try {
        value = await options.transport.call(schema, fn, args);
      } catch (cause) {
        const raw = rawError(cause);
        return err(raw ? mapDbError(raw, mappers) : toDbError(cause));
      }
      return ok(then(value));
    });
  }

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
