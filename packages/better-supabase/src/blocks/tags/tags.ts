import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type ExtraFields,
  type FieldsOf,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  isRecord,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";

export interface TagsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the tag's extra columns
   * (`blocks.tags.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `create` and `update`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Tags<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** A tag. `F` types the extra columns the `fields` schema describes. */
export interface Tag<F extends object = Record<never, never>> {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  /** Its rank key among the tenant's tags of the same kind, when it has one. */
  readonly rank?: string;
  /** Set on the tags `list` and `forSubject` return. */
  readonly kind?: string;
  readonly color?: string;
  readonly description?: string;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface Tags<F extends object = Record<never, never>> {
  /** Creates a tag; `fields` sets its extra columns. */
  create(
    organizationId: string,
    kind: string,
    name: string,
    color?: string,
    description?: string,
    fields?: Partial<F>,
  ): AsyncResult<Tag<F>>;
  /** Renames a tag (`name` null keeps it) and sets the extra columns `fields` names. */
  update(
    id: string,
    name: string | null,
    fields?: Partial<F>,
  ): AsyncResult<boolean>;
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
  /** The tenant's tags of `kind` (every kind without it), in rank order. */
  list(organizationId: string, kind?: string): AsyncResult<readonly Tag<F>[]>;
  /** The tags on one subject, in rank order; the caller must be able to read it. */
  forSubject(
    organizationId: string,
    subjectType: string,
    subjectId: string,
  ): AsyncResult<readonly Tag<F>[]>;
}

function tagOf(value: unknown): Tag {
  const row = recordOf(value, "tag");
  const optional = (key: "rank" | "kind" | "color" | "description") => {
    const found = optionalText(row[key]);
    return found === undefined ? {} : { [key]: found };
  };
  return {
    id: textOf(row["id"]),
    name: optionalText(row["name"]) ?? "",
    slug: optionalText(row["slug"]) ?? "",
    ...optional("rank"),
    ...optional("kind"),
    ...optional("color"),
    ...optional("description"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

const tagsOf = (value: unknown): Tag[] =>
  (Array.isArray(value) ? value : []).map(tagOf);

/** The `tags` SQL module as typed calls. */
export function createTags<S extends StandardSchemaV1 | undefined = undefined>(
  options: TagsOptions<S>,
): Tags<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "tag fields");
  const client: Tags<F> = {
    create: (organizationId, kind, name, color, description, extra) =>
      fields.args(extra).andThen((checked) =>
        call(
          "create_tag",
          {
            tenant: organizationId,
            kind,
            name,
            color: color ?? null,
            description: description ?? null,
            fields: checked,
          },
          (value) => ({ ...tagOf(value), name }),
        ).andThen(fields.row),
      ),
    update: (id, name, extra) =>
      fields
        .args(extra)
        .andThen((checked) =>
          call(
            "update_tag",
            { tag_id: id, name, fields: checked },
            (value) => value === true,
          ),
        ),
    reorder: (id, neighbors) => {
      const key = rankBetweenResult(neighbors);
      if (!key.ok) {
        return AsyncResult.err(key.error);
      }
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
    list: (organizationId, kind) =>
      call(
        "list_tags",
        { tenant: organizationId, kind: kind ?? null },
        tagsOf,
      ).andThen(fields.rows),
    forSubject: (organizationId, subjectType, subjectId) =>
      call(
        "subject_tags",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
        },
        tagsOf,
      ).andThen(fields.rows),
  };
  return withBlockHooks(client, options.hooks, {
    block: "tags",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
