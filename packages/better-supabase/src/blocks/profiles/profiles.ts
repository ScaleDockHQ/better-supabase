import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { applyTemporal, blockCall, isRecord, optionalText } from "../shared.ts";

export interface ProfilesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the profile columns the app adds
   * (`blocks.profiles.options.extraColumns`), keyed by database name. It types
   * and parses them on `mine()`, and validates them on `updateMine`, which
   * returns a `validation` error for a bad value. The parsed fields are merged
   * over the row, so the other columns stay.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around `mine` and `updateMine`. */
  readonly hooks?: NoInfer<BlockHooks<Profiles<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /**
   * Error mappers that run before the built-in ones, as in
   * `betterSupabase.mapError()`.
   */
  readonly mappers?: readonly ErrorMapper[];
  /**
   * Stores an avatar file for `setAvatar({ file })`, such as a Storage bucket's
   * `replace`: it uploads `file`, calls `commit` with the object path, then
   * removes `previous`. Without it, `setAvatar({ file })` fails with an
   * `invalid_request` error.
   */
  readonly avatarUploader?: AvatarUploader;
  /**
   * The managed column that holds the avatar's Storage path, by database name.
   * Default `avatar_path`.
   */
  readonly avatarColumn?: string;
}

/** What `setAvatar({ file })` hands the app's storage. */
export interface AvatarUpload {
  readonly file: Blob;
  /** The path the profile points at now, `null` for none. */
  readonly previous: string | null;
  /** Points the profile at the new object; fails when it can't. */
  readonly commit: (path: string) => AsyncResult<boolean>;
}

export type AvatarUploader = (input: AvatarUpload) => AsyncResult<unknown>;

/**
 * The caller's profile columns, by database name; `F` types the ones `fields`
 * describes.
 */
export type Profile<F extends object = Record<never, never>> = Readonly<
  Record<string, unknown>
> &
  F;

export interface Profiles<F extends object = Record<never, never>> {
  mine(): AsyncResult<Profile<F> | undefined>;
  updateMine(
    attrs: Readonly<Record<string, unknown>> & Partial<F>,
  ): AsyncResult<boolean>;
  /**
   * Points the profile at an avatar. `{ file }` uploads through
   * `options.avatarUploader` and then commits the path; `{ path }` commits a
   * path the app stored (`null` clears it). It calls `mine` and `updateMine`,
   * so their hooks see each step.
   */
  setAvatar(input: { file: Blob } | { path: string | null }): AsyncResult<true>;
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

  const fields: BlockFields<FieldsOf<S>> = blockFields(
    options.fields,
    "profile fields",
  );

  const column = options.avatarColumn ?? "avatar_path";

  const commit = (path: string | null): AsyncResult<boolean> =>
    // SAFETY: the avatar column is a managed column, not one of the typed
    // extra fields, so the Partial<F> part of the attrs doesn't cover it.
    hooked.updateMine({ [column]: path } as Readonly<Record<string, unknown>> &
      Partial<FieldsOf<S>>);

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
    setAvatar: (input) => {
      if ("path" in input) {
        return commit(input.path).map(() => true as const);
      }

      const { file } = input;
      const { avatarUploader } = options;

      if (avatarUploader === undefined) {
        return AsyncResult.from((): Promise<Result<true>> =>
          Promise.resolve(
            err(
              dbError(
                "invalid_request",
                "Pass avatarUploader to createProfiles to upload avatars",
              ),
            ),
          ),
        );
      }

      return hooked
        .mine()
        .andThen((profile) =>
          avatarUploader({
            file,
            previous: optionalText(profile?.[column]) ?? null,
            commit,
          }),
        )
        .map(() => true as const);
    },
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Profiles<FieldsOf<S>> = withBlockHooks(client, options.hooks, {
    block: "profiles",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
