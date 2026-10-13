import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";

import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import { blockCall, optionalText, recordOf, textOf } from "../shared.ts";

export interface TagsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Tag {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  /** Its rank key among the tenant's tags of the same kind, when it has one. */
  readonly rank?: string;
}

export interface Tags {
  create(
    organizationId: string,
    kind: string,
    name: string,
    color?: string,
    description?: string,
  ): AsyncResult<Tag>;
  update(id: string, name: string): AsyncResult<boolean>;
  /**
   * Moves a tag between the tags with rank keys `previous` and `next`.
   * Resolves to its new key.
   */
  reorder(id: string, neighbors: RankNeighbors): AsyncResult<string>;
  delete(id: string): AsyncResult<boolean>;
  tag(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    tagId: string,
  ): AsyncResult<boolean>;
  untag(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    tagId: string,
  ): AsyncResult<boolean>;
}

function tagOf(value: unknown): Tag {
  const row = recordOf(value, "tag");
  const rank = optionalText(row["rank"]);
  return {
    id: textOf(row["id"]),
    name: optionalText(row["name"]) ?? "",
    slug: optionalText(row["slug"]) ?? "",
    ...(rank === undefined ? {} : { rank }),
  };
}

export function createTags(options: TagsOptions): Tags {
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    create: (organizationId, kind, name, color, description) =>
      call(
        "create_tag",
        {
          tenant: organizationId,
          kind,
          name,
          color: color ?? null,
          description: description ?? null,
        },
        (value) => ({ ...tagOf(value), name }),
      ),
    update: (id, name) =>
      call("update_tag", { tag_id: id, name }, (value) => value === true),
    reorder: (id, neighbors) => {
      const key = rankBetweenResult(neighbors);
      if (!key.ok) return AsyncResult.err(key.error);
      return call("rank_tag", { tag_id: id, rank: key.data }, () => key.data);
    },
    delete: (id) =>
      call("delete_tag", { tag_id: id }, (value) => value === true),
    tag: (organizationId, subjectType, subjectId, tagId) =>
      call(
        "tag",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          tag_id: tagId,
        },
        (value) => value === true,
      ),
    untag: (organizationId, subjectType, subjectId, tagId) =>
      call(
        "untag",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          tag_id: tagId,
        },
        (value) => value === true,
      ),
  };
}
