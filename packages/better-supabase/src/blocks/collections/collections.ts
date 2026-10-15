import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  type CursorPageOptions,
  isRecord,
  oneOf,
  optionalInstant,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** Who sees a collection: its owner, a team, or the whole organization. */
export const COLLECTION_SCOPES = ["user", "team", "tenant"] as const;
export type CollectionScope = (typeof COLLECTION_SCOPES)[number];

/** A record in `config.subjects`. */
export interface CollectionSubject {
  readonly type: string;
  readonly id: string;
}

/** A named, static list of records of one subject type. */
export interface Collection {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly scope: CollectionScope;
  /** The owner of a personal (`user`) collection. */
  readonly ownerId?: string;
  /** The team of a `team` collection. */
  readonly teamId?: string;
  readonly name: string;
  readonly description?: string;
  readonly archived: boolean;
  readonly archivedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A record in a collection, with its title and URL from `config.subjects`. */
export interface CollectionEntry {
  readonly collectionId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly rank: string;
  readonly addedBy?: string;
  readonly addedAt: Temporal.Instant;
  readonly title?: string;
  readonly url?: string;
}

/** Where a page of entries stops: the last entry's rank and id. */
export interface CollectionEntryCursor {
  readonly rank: string;
  readonly subjectId: string;
}

export interface CollectionEntryPage {
  readonly items: readonly CollectionEntry[];
  /** Pass as `cursor` for the next page; `undefined` on the last page. */
  readonly next?: CollectionEntryCursor;
}

/** A record the caller starred, with its title and URL from `config.subjects`. */
export interface Star {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly rank: string;
  readonly starredAt: Temporal.Instant;
  readonly title?: string;
  readonly url?: string;
}

export interface CreateCollectionInput {
  readonly name: string;
  /** A type in `config.subjects` with a tenant column. */
  readonly subjectType: string;
  /** Default `user`. `team` and `tenant` need `collections.share`. */
  readonly scope?: CollectionScope;
  /** The team, for `scope: "team"`. */
  readonly teamId?: string;
  readonly description?: string;
}

export interface RenameCollectionInput {
  /** Left out keeps the name. */
  readonly name?: string;
  /** Left out keeps it; `null` clears it. */
  readonly description?: string | null;
}

export interface CollectionListOptions {
  /** Only collections of this subject type. */
  readonly subjectType?: string;
  /** Also archived collections. Default `false`. */
  readonly includeArchived?: boolean;
}

/** The most ids `add`, `remove` and `subjectIds` take or return. */
export const MAX_COLLECTION_IDS = 1000;

export interface Collections {
  /** Creates a collection. Shared scopes need `collections.share`. */
  create(
    organizationId: string,
    input: CreateCollectionInput,
  ): AsyncResult<Collection>;
  /** Renames a collection or changes its description. */
  rename(id: string, input: RenameCollectionInput): AsyncResult<Collection>;
  /** Archives a collection, or restores it with `archived: false`. */
  archive(id: string, archived?: boolean): AsyncResult<boolean>;
  /** The collections the caller sees, by name. */
  list(
    organizationId: string,
    options?: CollectionListOptions,
  ): AsyncResult<Collection[]>;
  /**
   * Adds records to the end of a collection, in the given order (at most
   * 1000). Ids already in it are skipped; resolves to the ids added.
   */
  add(
    id: string,
    subjectIds: readonly string[],
  ): AsyncResult<{ readonly added: readonly string[] }>;
  /** Removes records from a collection. Resolves to how many were removed. */
  remove(id: string, subjectIds: readonly string[]): AsyncResult<number>;
  /** Moves an entry between its neighbours' rank keys. Resolves to its new key. */
  reorder(
    id: string,
    subjectId: string,
    neighbors: RankNeighbors,
  ): AsyncResult<string>;
  /** A page of entries in rank order (default 50, at most 200). */
  entries(
    id: string,
    options?: CursorPageOptions<CollectionEntryCursor>,
  ): AsyncResult<CollectionEntryPage>;
  /** The ids of the records in a collection, in rank order (default 500, at most 1000). */
  subjectIds(
    id: string,
    options?: { readonly max?: number },
  ): AsyncResult<string[]>;
  /**
   * A repository `where` that keeps a list's rows to a collection's records,
   * for a saved view with `state.collectionId`: `{ [column]: { in: ids } }`.
   */
  where<const C extends string = "id">(
    id: string,
    options?: { readonly column?: C; readonly max?: number },
  ): AsyncResult<{ [K in C]: { in: string[] } }>;
  /** The active collections the caller sees that hold a record. */
  listsOf(subject: CollectionSubject): AsyncResult<Collection[]>;
  /** Stars a record at the end of the caller's favorites. */
  star(organizationId: string, subject: CollectionSubject): AsyncResult<Star>;
  /** Resolves to `false` when the record wasn't starred. */
  unstar(subject: CollectionSubject): AsyncResult<boolean>;
  /** The caller's stars in sidebar order, of one subject type with `type`. */
  starred(
    organizationId: string,
    options?: { readonly type?: string },
  ): AsyncResult<Star[]>;
  /** Moves a star between its neighbours' rank keys. Resolves to its new key. */
  reorderStar(
    subject: CollectionSubject,
    neighbors: RankNeighbors,
  ): AsyncResult<string>;
}

export interface CollectionsOptions {
  readonly transport: BlockTransport;
  /** `blocks.collections.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Collections>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** `{ [key]: value }`, or nothing when `value` is undefined. */
function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): Partial<Record<K, V>> {
  const out: Partial<Record<K, V>> = {};
  if (value !== undefined) out[key] = value;
  return out;
}

function collectionOf(value: unknown): Collection {
  const row = recordOf(value, "collection");
  const archivedAt = optionalInstant(row["archivedAt"]);
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    scope: oneOf(row["scope"], COLLECTION_SCOPES, "user"),
    name: textOf(row["name"]),
    archived: archivedAt !== undefined,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("teamId", optionalText(row["teamId"])),
    ...optional("description", optionalText(row["description"])),
    ...optional("archivedAt", archivedAt),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function entryOf(value: unknown): CollectionEntry {
  const row = recordOf(value, "collection entry");
  return {
    collectionId: textOf(row["collectionId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    rank: textOf(row["rank"]),
    addedAt: requiredInstant(row["addedAt"], "addedAt"),
    ...optional("addedBy", optionalText(row["addedBy"])),
    ...optional("title", optionalText(row["title"])),
    ...optional("url", optionalText(row["url"])),
  };
}

function starOf(value: unknown): Star {
  const row = recordOf(value, "star");
  return {
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    rank: textOf(row["rank"]),
    starredAt: requiredInstant(row["starredAt"], "starredAt"),
    ...optional("title", optionalText(row["title"])),
    ...optional("url", optionalText(row["url"])),
  };
}

function entryPage(
  rows: readonly CollectionEntry[],
  limit: number | undefined,
): CollectionEntryPage {
  const last = rows.at(-1);
  return rows.length === (limit ?? 50) && last !== undefined
    ? { items: rows, next: { rank: last.rank, subjectId: last.subjectId } }
    : { items: rows };
}

/**
 * The collections block: favorites (a member's starred records, ranked for
 * a sidebar) and lists (named, static collections of one subject type owned
 * by a user, a team or the organization) on any record in `config.subjects`.
 */
export function createCollections(options: CollectionsOptions): Collections {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const subjectIds = (id: string, max: number | undefined) =>
    call(
      "collection_subject_ids",
      { collection: id, max_ids: max ?? null },
      (value) => [...stringsOf(value)],
    );
  const client: Collections = {
    create: (organizationId, input) =>
      call(
        "create_collection",
        {
          tenant: organizationId,
          subject_type: input.subjectType,
          name: input.name,
          scope: input.scope ?? "user",
          team: input.teamId ?? null,
          description: input.description ?? null,
        },
        collectionOf,
      ),
    rename: (id, input) =>
      call(
        "rename_collection",
        {
          collection: id,
          name: input.name ?? null,
          description:
            input.description === undefined ? null : (input.description ?? ""),
        },
        collectionOf,
      ),
    archive: (id, archived = true) =>
      call(
        "archive_collection",
        { collection: id, archived },
        (value) => value === true,
      ),
    list: (organizationId, listOptions = {}) =>
      call(
        "list_collections",
        {
          tenant: organizationId,
          subject_type: listOptions.subjectType ?? null,
          include_archived: listOptions.includeArchived ?? false,
        },
        (value) => recordsOf(value, "list_collections").map(collectionOf),
      ),
    add: (id, ids) =>
      call(
        "add_collection_entries",
        { collection: id, subject_ids: [...ids], subject_type: null },
        (value) => ({
          added: isRecord(value) ? [...stringsOf(value["added"])] : [],
        }),
      ),
    remove: (id, ids) =>
      call(
        "remove_collection_entries",
        { collection: id, subject_ids: [...ids] },
        Number,
      ),
    reorder: (id, subjectId, neighbors) => {
      const key = rankBetweenResult(neighbors);
      if (!key.ok) return AsyncResult.err(key.error);
      return call(
        "rank_collection_entry",
        { collection: id, subject_id: subjectId, rank: key.data },
        () => key.data,
      );
    },
    entries: (id, pageOptions = {}) => {
      const { limit, cursor } = pageOf(pageOptions);
      return call(
        "collection_entries",
        {
          collection: id,
          after_rank: cursor?.rank ?? null,
          after_id: cursor?.subjectId ?? null,
          page_size: limit ?? null,
        },
        (value) =>
          entryPage(recordsOf(value, "collection_entries").map(entryOf), limit),
      );
    },
    subjectIds: (id, idOptions = {}) => subjectIds(id, idOptions.max),
    where: (id, whereOptions = {}) =>
      subjectIds(id, whereOptions.max).map(
        (ids) =>
          // SAFETY: the one key is the column the caller named, "id" by default.
          ({ [whereOptions.column ?? "id"]: { in: ids } }) as {
            [K in NonNullable<typeof whereOptions.column>]: { in: string[] };
          },
      ),
    listsOf: (subject) =>
      call(
        "collections_of",
        { subject_type: subject.type, subject_id: subject.id },
        (value) => recordsOf(value, "collections_of").map(collectionOf),
      ),
    star: (organizationId, subject) =>
      call(
        "star_subject",
        {
          tenant: organizationId,
          subject_type: subject.type,
          subject_id: subject.id,
        },
        starOf,
      ),
    unstar: (subject) =>
      call(
        "unstar_subject",
        { subject_type: subject.type, subject_id: subject.id },
        (value) => value === true,
      ),
    starred: (organizationId, starredOptions = {}) =>
      call(
        "starred_subjects",
        { tenant: organizationId, subject_type: starredOptions.type ?? null },
        (value) => recordsOf(value, "starred_subjects").map(starOf),
      ),
    reorderStar: (subject, neighbors) => {
      const key = rankBetweenResult(neighbors);
      if (!key.ok) return AsyncResult.err(key.error);
      return call(
        "rank_star",
        { subject_type: subject.type, subject_id: subject.id, rank: key.data },
        () => key.data,
      );
    },
  };
  return withBlockHooks(client, options.hooks, {
    block: "collections",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
