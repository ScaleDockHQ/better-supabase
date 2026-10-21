import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";
import type { JsonPatchOperation, JsonValue } from "./json-patch.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { subjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { createPatch } from "./json-patch.ts";

export interface VersionsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the version's extra columns
   * (`blocks.versions.options.extraColumns`), keyed by database name. It types
   * and parses them on `list` and `get`, and validates them on `snapshot`.
   * `getShared` leaves them out.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Versions<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export type VersionSource = "manual" | "auto" | "restore";

const SOURCES: readonly VersionSource[] = ["manual", "auto", "restore"];

/** One version of a subject. `content` is there when it was read with `get`. */
export interface Version<F extends object = Record<never, never>> {
  readonly id: string;
  readonly number: number;
  readonly subject: SubjectRef;
  /** A named version is kept out of retention. */
  readonly label?: string;
  readonly source: VersionSource;
  /** Written by a state change (`freeze`); it can't be relabeled or deleted. */
  readonly frozen: boolean;
  readonly contentHash: string;
  /** A Storage path, for content kept outside the table. */
  readonly storagePath?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly content?: JsonValue;
  /** The extra columns, keyed by database name; empty from `getShared`. */
  readonly fields: ExtraFields<F>;
}

export interface SnapshotInput<F extends object = Record<never, never>> {
  /**
   * The content to keep. Leave it out to copy the subject's `columns`
   * (`blocks.versions.options.subjects.<type>.columns`).
   */
  readonly content?: JsonValue;
  readonly label?: string;
  readonly storagePath?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface SnapshotResult {
  readonly id: string;
  readonly number: number;
  readonly contentHash: string;
  /**
   * `true` when the content matched the latest version, which is returned
   * instead.
   */
  readonly unchanged: boolean;
}

export interface RestoreResult extends SnapshotResult {
  /** The number of the version that was restored. */
  readonly restoredFrom: number;
  readonly content: JsonValue;
}

export interface VersionListOptions {
  readonly pageSize?: number;
  /** Versions numbered below this one, for the next page. */
  readonly before?: number;
}

/**
 * `F` is the extra fields `options.fields` describes. `snapshot` and `list` act
 * in the block's `tenant`.
 */
export interface Versions<F extends object = Record<never, never>> {
  /** Records a version of `subject`. */
  snapshot(
    subject: SubjectRef,
    input?: SnapshotInput<F>,
  ): AsyncResult<SnapshotResult>;
  /** A subject's versions, newest first, without content. */
  list(
    subject: SubjectRef,
    options?: VersionListOptions,
  ): AsyncResult<readonly Version<F>[]>;
  get(id: string): AsyncResult<Version<F>>;
  /**
   * The version a share link is pinned to, with its content, read with the
   * token alone (anon). `null` for an unknown, revoked or expired token, or a
   * link without a version. Needs the share-links module.
   */
  getShared(token: string): AsyncResult<Version | null>;
  /** Writes the version back to its subject and records that as a new version. */
  restore(id: string): AsyncResult<RestoreResult>;
  /**
   * Writes only `fields` of the version back; the subject's other columns keep
   * their current values. Needs a subject type with `columns`.
   */
  restoreFields(
    id: string,
    fields: readonly string[],
  ): AsyncResult<RestoreResult>;
  /** Names a version, which keeps it; `null` removes the name. */
  label(id: string, label: string | null): AsyncResult<boolean>;
  delete(id: string): AsyncResult<boolean>;
  /** The RFC 6902 patch from version `fromId` to version `toId`. */
  diff(fromId: string, toId: string): AsyncResult<JsonPatchOperation[]>;
}

function versionOf(value: unknown, fn: string): Version {
  const row = recordOf(value, fn);
  const label = optionalText(row["label"]);
  const storagePath = optionalText(row["storagePath"]);
  const createdBy = optionalText(row["createdBy"]);

  return {
    id: textOf(row["id"]),
    number: Number(row["number"]),
    subject: subjectRefOf(row["subjectType"], row["subjectId"]),
    source: enumOrThrow(row["source"], SOURCES, "version source"),
    frozen: row["frozen"] === true,
    contentHash: textOf(row["contentHash"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(label === undefined ? {} : { label }),
    ...(storagePath === undefined ? {} : { storagePath }),
    ...(createdBy === undefined ? {} : { createdBy }),
    ...("content" in row ? { content: jsonOf(row["content"]) } : {}),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

// SAFETY: jsonb arrives parsed, so it is a JSON value.
const jsonOf = (value: unknown): JsonValue => (value ?? null) as JsonValue;

function snapshotOf(value: unknown, fn: string): SnapshotResult {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    number: Number(row["number"]),
    contentHash: textOf(row["contentHash"]),
    unchanged: row["unchanged"] === true,
  };
}

/** The `versions` SQL module as typed calls. */

function restoreOf(value: unknown): RestoreResult {
  const row = recordOf(value, "restore_version");

  return {
    ...snapshotOf(row, "restore_version"),
    restoredFrom: Number(row["restoredFrom"]),
    content: jsonOf(row["content"]),
  };
}

export function createVersions<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: VersionsOptions<S>): Versions<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "version fields");
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const get = (id: string): AsyncResult<Version<F>> =>
    call("get_version", { version_id: id }, (value) =>
      versionOf(value, "get_version"),
    ).andThen(fields.row);

  const client: Versions<F> = {
    getShared: (token) =>
      call("get_shared_version", { token }, (value) =>
        value === null || value === undefined
          ? null
          : versionOf(value, "get_shared_version"),
      ),
    snapshot: (subject, input = {}) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "snapshot_version",
              {
                tenant: organizationId,
                subject_type: subject.type,
                subject_id: subject.id,
                content: input.content ?? null,
                label: input.label ?? null,
                storage_path: input.storagePath ?? null,
                fields: checked,
              },
              (value) => snapshotOf(value, "snapshot_version"),
            ),
          ),
      ),
    list: (subject, page = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_versions",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            page_size: page.pageSize ?? null,
            before: page.before ?? null,
          },
          (value) =>
            recordsOf(value, "list_versions").map((row) =>
              versionOf(row, "list_versions"),
            ),
        ).andThen(fields.rows),
      ),
    get,
    restore: (id) => call("restore_version", { version_id: id }, restoreOf),
    restoreFields: (id, fields) =>
      call(
        "restore_version",
        { version_id: id, fields: [...fields] },
        restoreOf,
      ),
    label: (id, label) =>
      call(
        "label_version",
        { version_id: id, label },
        (value) => value === true,
      ),
    delete: (id) =>
      call("delete_version", { version_id: id }, (value) => value === true),
    diff: (fromId, toId) =>
      get(fromId).andThen((from) =>
        get(toId).map((to) =>
          createPatch(from.content ?? null, to.content ?? null),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "versions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
