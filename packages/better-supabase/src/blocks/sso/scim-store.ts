import type { BlockTransport } from "../../core/block-transport.ts";
import type { Result } from "../../core/result.ts";
import type { ScimFilter } from "./scim-filter.ts";

import { ok } from "../../core/result.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";
import { SCIM_GROUP, SCIM_USER } from "./scim-schema.ts";

export type ScimResourceType = "User" | "Group";

type Doc = Readonly<Record<string, unknown>>;

/**
 * A resource as a store keeps it: the SCIM attributes without `meta` and
 * without `$ref`s, which the handler adds for the URL it serves.
 */
export interface ScimStoredResource {
  readonly id: string;
  readonly resource: Doc;
  /** Raised on every write; the ETag is `W/"<version>"`. */
  readonly version: number;
  readonly created: Temporal.Instant;
  readonly lastModified: Temporal.Instant;
}

export interface ScimListQuery {
  /** The parsed `filter`; a store may apply it or leave it to the handler. */
  readonly filter: ScimFilter | undefined;
  /** 1-based, as in RFC 7644 §3.4.2.4. */
  readonly startIndex: number;
  readonly count: number;
}

export interface ScimListPage {
  readonly resources: readonly ScimStoredResource[];
  /**
   * Set when the store applied `filter`, `startIndex` and `count` itself: the
   * handler then pages nothing and reports this total. Leave it out to return
   * every resource of the tenant for the handler to filter and page.
   */
  readonly totalResults?: number;
}

export interface ScimSaveInput {
  /** `undefined` creates the resource. */
  readonly id: string | undefined;
  /**
   * The resource the client sent, or the result of a PATCH, without `meta`.
   * Extension schemas and their attributes are left in.
   */
  readonly resource: Doc;
  /**
   * The core attributes the handler validated. Users: `userName`, `externalId`,
   * `displayName`, `givenName`, `familyName`, `emails` and `active`. Groups:
   * `displayName`, `externalId` and `members` (ids).
   */
  readonly data: Doc;
  /** The version an `If-Match` (or the read before a PUT or PATCH) requires. */
  readonly version: number | undefined;
}

/**
 * Where the SCIM handler keeps users and groups. `sqlScimStore` is the default;
 * another store can relay to a directory or a provider. Errors are `DbError`s:
 * `not_found` answers 404, `stale` 412, `conflict` 409, and `invalid_input` or
 * `validation` 400.
 */
export interface ScimStore {
  readonly apiVersion: 1;
  list(
    type: ScimResourceType,
    tenant: string,
    query: ScimListQuery,
  ): Promise<Result<ScimListPage>>;
  /** `undefined` when the tenant has no resource with this id. */
  get(
    type: ScimResourceType,
    tenant: string,
    id: string,
  ): Promise<Result<ScimStoredResource | undefined>>;
  save(
    type: ScimResourceType,
    tenant: string,
    input: ScimSaveInput,
  ): Promise<Result<ScimStoredResource>>;
  /** `false` when the tenant has no resource with this id. */
  delete(
    type: ScimResourceType,
    tenant: string,
    id: string,
  ): Promise<Result<boolean>>;
}

export interface SqlScimStoreOptions {
  readonly schema?: string | undefined;
}

function compact(doc: Record<string, unknown>): Doc {
  return Object.fromEntries(
    Object.entries(doc).filter(([, value]) => value !== undefined),
  );
}

function userResource(row: Doc): Doc {
  const givenName = optionalText(row["given_name"]);
  const familyName = optionalText(row["family_name"]);

  return compact({
    schemas: [SCIM_USER],
    id: textOf(row["id"]),
    externalId: optionalText(row["external_id"]),
    userName: textOf(row["user_name"]),
    name:
      givenName === undefined && familyName === undefined
        ? undefined
        : compact({
            givenName,
            familyName,
            formatted: [givenName, familyName].filter(Boolean).join(" "),
          }),
    displayName: optionalText(row["display_name"]),
    emails: Array.isArray(row["emails"]) ? row["emails"] : [],
    active: row["active"] !== false,
    groups: recordsOf(row["groups"], "scim_users.groups").map((group) => ({
      value: textOf(group["value"]),
      display: textOf(group["display"]),
    })),
  });
}

function groupResource(row: Doc): Doc {
  return compact({
    schemas: [SCIM_GROUP],
    id: textOf(row["id"]),
    externalId: optionalText(row["external_id"]),
    displayName: textOf(row["display_name"]),
    members: recordsOf(row["members"], "scim_groups.members").map((member) => ({
      value: textOf(member["value"]),
      display: textOf(member["display"]),
    })),
  });
}

const FUNCTIONS = {
  User: {
    table: "scim_users",
    list: "scim_list_users",
    get: "scim_get_user",
    save: "scim_save_user",
    remove: "scim_delete_user",
    of: userResource,
  },
  Group: {
    table: "scim_groups",
    list: "scim_list_groups",
    get: "scim_get_group",
    save: "scim_save_group",
    remove: "scim_delete_group",
    of: groupResource,
  },
} as const;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function stored(type: ScimResourceType, value: unknown): ScimStoredResource {
  const row = recordOf(value, FUNCTIONS[type].table);

  return {
    id: textOf(row["id"]),
    resource: FUNCTIONS[type].of(row),
    version: Number(row["version"]),
    created: toInstant(textOf(row["created_at"])),
    lastModified: toInstant(textOf(row["updated_at"])),
  };
}

/**
 * The SCIM store over the sso module's `scim_*` functions. Needs a service-role
 * transport. It keeps the core attributes only, so extension attributes are not
 * stored; the handler leaves the filter and paging to itself.
 */
export function sqlScimStore(
  transport: BlockTransport,
  options: SqlScimStoreOptions = {},
): ScimStore {
  const call = blockCall(transport, options.schema);

  return {
    apiVersion: 1,
    list: async (type, tenant) =>
      call(FUNCTIONS[type].list, { tenant }, (value) => ({
        resources: recordsOf(value, FUNCTIONS[type].list).map((row) =>
          stored(type, row),
        ),
      })),
    get: async (type, tenant, id) =>
      UUID.test(id)
        ? call(FUNCTIONS[type].get, { tenant, id }, (value) =>
            isRecord(value) ? stored(type, value) : undefined,
          )
        : ok(undefined),
    save: async (type, tenant, input) =>
      call(
        FUNCTIONS[type].save,
        {
          tenant,
          id: input.id ?? null,
          data: input.data,
          version: input.version ?? null,
        },
        (value) => stored(type, value),
      ),
    delete: async (type, tenant, id) =>
      UUID.test(id)
        ? call(
            FUNCTIONS[type].remove,
            { tenant, id },
            (value) => value === true,
          )
        : ok(false),
  };
}

export type ScimSyncOperation = "create" | "replace" | "patch" | "delete";

/** One SCIM write, as the sync log records it. */
export interface ScimSyncEntry {
  readonly tenant: string;
  readonly operation: ScimSyncOperation;
  readonly resourceType: ScimResourceType;
  /** `undefined` for a create that failed. */
  readonly resourceId: string | undefined;
  /** The HTTP status the handler answered. */
  readonly status: number;
  /** The SCIM `detail` of a failed write. */
  readonly error: string | undefined;
  readonly requestId: string | undefined;
}

/**
 * Records SCIM writes. The handler waits for `record` but ignores its failures,
 * so a log can never change an answer.
 */
export interface ScimSyncLog {
  readonly apiVersion: 1;
  record(entry: ScimSyncEntry): Promise<unknown>;
}

/**
 * The sync log over `scim_sync_log` (`blocks.sso.options.syncLog`). Needs a
 * service-role transport.
 */
export function sqlScimSyncLog(
  transport: BlockTransport,
  options: SqlScimStoreOptions = {},
): ScimSyncLog {
  const call = blockCall(transport, options.schema);

  return {
    apiVersion: 1,
    record: async (entry) =>
      call(
        "scim_log_sync",
        {
          tenant: entry.tenant,
          operation: entry.operation,
          resource_type: entry.resourceType,
          resource_id: entry.resourceId ?? null,
          status: entry.status,
          error: entry.error ?? null,
          request_id: entry.requestId ?? null,
        },
        () => null,
      ),
  };
}
