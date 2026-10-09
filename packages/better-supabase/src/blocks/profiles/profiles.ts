import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import { blockFields, type FieldsOf } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  isRecord,
} from "../shared.ts";

export interface ProfilesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `sql.modules.profiles.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /**
   * A Standard Schema for the profile columns the app adds
   * (`sql.modules.profiles.options.extraColumns`), keyed by database name.
   * It types and parses them on `mine()`, and validates them on
   * `updateMine`, which returns a `validation` error for a bad value. The
   * parsed fields are merged over the row, so the other columns stay.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around `mine` and `updateMine`. */
  readonly hooks?: NoInfer<BlockHooks<Profiles<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** Error mappers that run before the built-in ones, as in `betterSupabase.mapError()`. */
  readonly mappers?: readonly ErrorMapper[];
}

/** The caller's profile columns, by database name; `F` types the ones `fields` describes. */
export type Profile<F extends object = Record<never, never>> = Readonly<
  Record<string, unknown>
> &
  F;

export interface Profiles<F extends object = Record<never, never>> {
  mine(): AsyncResult<Profile<F> | undefined>;
  updateMine(
    attrs: Readonly<Record<string, unknown>> & Partial<F>,
  ): AsyncResult<boolean>;
}

/**
 * The `profiles` SQL module as typed calls. `mine` and `updateMine` are the
 * functions a signed-in user runs on their own row.
 */
export function createProfiles<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ProfilesOptions<S>): Profiles<FieldsOf<S>> {
  applyTemporal(options);
  const run = blockCall(
    options.transport,
    options.schema,
    options.mappers ?? [],
  );
  const fields = blockFields<FieldsOf<S>>(options.fields, "profile fields");

  const client: Profiles<FieldsOf<S>> = {
    mine() {
      return run("my_profile", {}, (value) =>
        isRecord(value) ? value : undefined,
      ).andThen(async (row) =>
        row === undefined ? ok(row) : fields.read(row),
      );
    },
    updateMine(attrs) {
      return AsyncResult.from(() => fields.write(attrs)).andThen((valid) =>
        run("update_my_profile", { attrs: valid }, (value) => value === true),
      );
    },
  };
  return withBlockHooks(client, options.hooks, {
    block: "profiles",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
