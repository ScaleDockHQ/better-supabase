import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import {
  entityList,
  foundOrNotFound,
  tenantOrOption,
} from "../../core/entity-list.ts";
import {
  instantOf,
  oneOf,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { collectionListSurface } from "./lists.ts";

/**
 * `automatic` collections show up in every search of their tenant, `restricted`
 * ones only for their grants and admins, `disabled` ones in no search.
 */
export type KnowledgeVisibility = "automatic" | "restricted" | "disabled";

export interface KnowledgeCollection {
  readonly id: string;
  /** None for a system collection, which every tenant reads. */
  readonly organizationId: string | undefined;
  readonly name: string;
  readonly description: string | undefined;
  readonly visibility: KnowledgeVisibility;
  /** A search ranks the chunks of a higher priority collection first. */
  readonly priority: number;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface NewKnowledgeCollection {
  readonly name: string;
  readonly description?: string;
  /** Default `automatic`. */
  readonly visibility?: KnowledgeVisibility;
  /** Default 0. */
  readonly priority?: number;
}

/** A user or a team a restricted collection is granted to. */
export type KnowledgeGrantee =
  | { readonly userId: string }
  | { readonly teamId: string };

export interface KnowledgeCollectionGrant {
  readonly userId: string | undefined;
  readonly teamId: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface KnowledgeCollections {
  /**
   * Creates a collection. `organizationId` null creates a system collection
   * (service role).
   */
  create(input: {
    organizationId: string | null;
    collection: NewKnowledgeCollection;
  }): AsyncResult<KnowledgeCollection>;
  update(input: {
    collectionId: string;
    patch: Partial<NewKnowledgeCollection>;
  }): AsyncResult<KnowledgeCollection>;
  /** Deletes a collection; its documents stay, without a collection. */
  remove(collectionId: string): AsyncResult<boolean>;
  /**
   * The collections the caller reads, system ones included.
   *
   * @deprecated Use `page`, which pages by keyset and takes `q`, sorts, array
   * filters and a count (ADR 1077).
   */
  list(organizationId: string): AsyncResult<readonly KnowledgeCollection[]>;
  /**
   * One keyset page of collections, highest priority first. `filters` takes
   * `visibility` as a list; `q` searches the name and description.
   */
  page(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<KnowledgeCollection>>;
  /** The values of the `visibility` facet and how many collections hold each. */
  facets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many collections match the page's filters. */
  count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** One collection by id, or a `not_found` error. */
  get(collectionId: string): AsyncResult<KnowledgeCollection>;
  grant(input: {
    collectionId: string;
    to: KnowledgeGrantee;
  }): AsyncResult<boolean>;
  revoke(input: {
    collectionId: string;
    from: KnowledgeGrantee;
  }): AsyncResult<boolean>;
  grants(
    collectionId: string,
  ): AsyncResult<readonly KnowledgeCollectionGrant[]>;
}

const VISIBILITIES: readonly KnowledgeVisibility[] = [
  "automatic",
  "restricted",
  "disabled",
];

function collectionOf(value: unknown): KnowledgeCollection {
  const row = recordOf(value, "knowledge_collections");

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["tenant_id"]),
    name: textOf(row["name"]),
    description: optionalText(row["description"]),
    visibility: oneOf(textOf(row["visibility"]), VISIBILITIES, "disabled"),
    priority: Number(row["priority"] ?? 0),
    createdBy: optionalText(row["created_by"]),
    createdAt: instantOf(row["created_at"]),
    updatedAt: instantOf(row["updated_at"]),
  };
}

const granteeArgs = (
  grantee: KnowledgeGrantee,
): { readonly user_id?: string; readonly team_id?: string } =>
  "userId" in grantee
    ? { user_id: grantee.userId }
    : { team_id: grantee.teamId };

/** The collection methods of `createKnowledge`, over its user transport. */
export function knowledgeCollections(call: BlockCall): KnowledgeCollections {
  const setGrant = (
    collectionId: string,
    grantee: KnowledgeGrantee,
    granted: boolean,
  ): AsyncResult<boolean> =>
    call(
      "set_knowledge_collection_grant",
      { collection_id: collectionId, ...granteeArgs(grantee), granted },
      (value) => value === true,
    );

  const pages = entityList<KnowledgeCollection, RequiredTenantOption>({
    entity: "knowledge_collection",
    surface: collectionListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_knowledge_collections",
    rowOf: (row) => collectionOf(row),
  });

  return {
    page: pages.page,
    facets: pages.facets,
    count: pages.count,
    get: (collectionId) =>
      call(
        "get_knowledge_collection",
        { collection_id: collectionId },
        (value) =>
          value === null || value === undefined
            ? undefined
            : collectionOf(value),
      ).andThen((row) =>
        foundOrNotFound("knowledge_collection", row, collectionId),
      ),
    create: ({ organizationId, collection }) =>
      call(
        "create_knowledge_collection",
        {
          tenant: organizationId,
          name: collection.name,
          description: collection.description,
          visibility: collection.visibility,
          priority: collection.priority,
        },
        collectionOf,
      ),
    update: ({ collectionId, patch }) =>
      call(
        "update_knowledge_collection",
        { collection_id: collectionId, patch },
        collectionOf,
      ),
    remove: (collectionId) =>
      call(
        "delete_knowledge_collection",
        { collection_id: collectionId },
        (value) => value === true,
      ),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    list: (organizationId) =>
      call("list_knowledge_collections", { tenant: organizationId }, (value) =>
        recordsOf(value, "knowledge_collections").map(collectionOf),
      ),
    grant: ({ collectionId, to }) => setGrant(collectionId, to, true),
    revoke: ({ collectionId, from }) => setGrant(collectionId, from, false),
    grants: (collectionId) =>
      call(
        "list_knowledge_collection_grants",
        { collection_id: collectionId },
        (value) =>
          recordsOf(value, "knowledge_collection_grants").map((row) => ({
            userId: optionalText(row["user_id"]),
            teamId: optionalText(row["team_id"]),
            createdAt: instantOf(row["created_at"]),
          })),
      ),
  };
}
