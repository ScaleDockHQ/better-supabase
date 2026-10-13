import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

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
  return {
    id: textOf(row["id"]),
    name: optionalText(row["name"]) ?? "",
    slug: optionalText(row["slug"]) ?? "",
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
