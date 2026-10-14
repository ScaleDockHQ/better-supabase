import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { JsonPatchOperation, JsonValue } from "./json-patch.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { createPatch } from "./json-patch.ts";

export interface VersionsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `sql.modules.versions.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Versions>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type VersionSource = "manual" | "auto" | "restore";

const SOURCES: readonly VersionSource[] = ["manual", "auto", "restore"];

/** One version of a subject. `content` is there when it was read with `get`. */
export interface Version {
  readonly id: string;
  readonly number: number;
  readonly subjectType: string;
  readonly subjectId: string;
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
}

export interface SnapshotInput {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /**
   * The content to keep. Leave it out to copy the subject's `columns`
   * (`sql.modules.versions.options.subjects.<type>.columns`).
   */
  readonly content?: JsonValue;
  readonly label?: string;
  readonly storagePath?: string;
}

export interface SnapshotResult {
  readonly id: string;
  readonly number: number;
  readonly contentHash: string;
  /** `true` when the content matched the latest version, which is returned instead. */
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

export interface Versions {
  snapshot(input: SnapshotInput): AsyncResult<SnapshotResult>;
  /** Newest first, without content. */
  list(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    options?: VersionListOptions,
  ): AsyncResult<readonly Version[]>;
  get(id: string): AsyncResult<Version>;
  /**
   * The version a share link is pinned to, with its content, read with the
   * token alone (anon). `null` for an unknown, revoked or expired token, or
   * a link without a version. Needs the share-links module.
   */
  getShared(token: string): AsyncResult<Version | null>;
  /** Writes the version back to its subject and records that as a new version. */
  restore(id: string): AsyncResult<RestoreResult>;
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
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    source: enumOrThrow(row["source"], SOURCES, "version source"),
    frozen: row["frozen"] === true,
    contentHash: textOf(row["contentHash"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(label === undefined ? {} : { label }),
    ...(storagePath === undefined ? {} : { storagePath }),
    ...(createdBy === undefined ? {} : { createdBy }),
    ...("content" in row ? { content: jsonOf(row["content"]) } : {}),
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
export function createVersions(options: VersionsOptions): Versions {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const get = (id: string): AsyncResult<Version> =>
    call("get_version", { version_id: id }, (value) =>
      versionOf(value, "get_version"),
    );
  const client: Versions = {
    getShared: (token) =>
      call("get_shared_version", { token }, (value) =>
        value === null || value === undefined
          ? null
          : versionOf(value, "get_shared_version"),
      ),
    snapshot: (input) =>
      call(
        "snapshot_version",
        {
          tenant: input.organizationId,
          subject_type: input.subjectType,
          subject_id: input.subjectId,
          content: input.content ?? null,
          label: input.label ?? null,
          storage_path: input.storagePath ?? null,
        },
        (value) => snapshotOf(value, "snapshot_version"),
      ),
    list: (organizationId, subjectType, subjectId, page = {}) =>
      call(
        "list_versions",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          page_size: page.pageSize ?? null,
          before: page.before ?? null,
        },
        (value) =>
          recordsOf(value, "list_versions").map((row) =>
            versionOf(row, "list_versions"),
          ),
      ),
    get,
    restore: (id) =>
      call("restore_version", { version_id: id }, (value) => {
        const row = recordOf(value, "restore_version");
        return {
          ...snapshotOf(row, "restore_version"),
          restoredFrom: Number(row["restoredFrom"]),
          content: jsonOf(row["content"]),
        };
      }),
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
