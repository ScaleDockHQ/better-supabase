import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import {
  instantOf,
  oneOf,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

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
  create(
    organizationId: string | null,
    collection: NewKnowledgeCollection,
  ): AsyncResult<KnowledgeCollection>;
  update(
    collectionId: string,
    patch: Partial<NewKnowledgeCollection>,
  ): AsyncResult<KnowledgeCollection>;
  /** Deletes a collection; its documents stay, without a collection. */
  remove(collectionId: string): AsyncResult<boolean>;
  /** The collections the caller reads, system ones included. */
  list(organizationId: string): AsyncResult<readonly KnowledgeCollection[]>;
  grant(collectionId: string, to: KnowledgeGrantee): AsyncResult<boolean>;
  revoke(collectionId: string, from: KnowledgeGrantee): AsyncResult<boolean>;
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
    organizationId: optionalText(row["organization_id"]),
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

  return {
    create: (organizationId, collection) =>
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
    update: (collectionId, patch) =>
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
    list: (organizationId) =>
      call("list_knowledge_collections", { tenant: organizationId }, (value) =>
        recordsOf(value, "knowledge_collections").map(collectionOf),
      ),
    grant: (collectionId, to) => setGrant(collectionId, to, true),
    revoke: (collectionId, from) => setGrant(collectionId, from, false),
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
