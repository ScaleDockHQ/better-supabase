import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  neighborsForIndex,
  rankBetweenResult,
} from "../../core/rank-result.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
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
   * (`blocks.tags.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on `create` and `update`.
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
  /** Set on the tags `list` returns. */
  readonly kind?: string;
  readonly color?: string;
  readonly description?: string;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** The input of `tags.create`. */
export interface CreateTagInput<F extends object = Record<never, never>> {
  /** The record type the tag is for, such as `deal`. */
  readonly kind: string;
  readonly name: string;
  readonly color?: string;
  readonly description?: string;
  /**
   * The slug, lowercase letters and digits joined by single hyphens. Derived
   * from `name` when left out.
   */
  readonly slug?: string;
  /** The extra columns, validated by the `fields` schema. */
  readonly fields?: Partial<F>;
}

/**
 * The patch `tags.update` takes. A key that is left out keeps its value; `null`
 * clears `color` or `description`.
 */
export interface UpdateTagInput<F extends object = Record<never, never>> {
  readonly name?: string;
  readonly slug?: string;
  readonly kind?: string;
  readonly color?: string | null;
  readonly description?: string | null;
  /** The extra columns to set; the others keep their values. */
  readonly fields?: Partial<F>;
}

const PATCH_KEYS = ["slug", "kind", "color", "description"] as const;

/** The filter `tags.list` takes. */
export interface ListTagsParams {
  /** Only the tags of this kind. */
  readonly kind?: string;
  /** Only the tags on this record; the caller must be able to read it. */
  readonly on?: RecordRef;
}

/**
 * `F` is the extra fields `options.fields` describes. Every method that takes
 * no tag id acts in the block's `tenant`.
 */
export interface Tags<F extends object = Record<never, never>> {
  /** Creates a tag in the tenant. */
  create(input: CreateTagInput<F>): AsyncResult<Tag<F>>;
  /**
   * Renames a tag, sets its slug, kind, color or description, and sets the
   * extra columns `fields` names.
   */
  update(input: { id: string; patch: UpdateTagInput<F> }): AsyncResult<boolean>;
  /**
   * Moves a tag between the tags with rank keys `previous` and `next`. Resolves
   * to its new key.
   */
  reorder(input: { id: string; neighbors: RankNeighbors }): AsyncResult<string>;
  /**
   * Puts a tag at position `toIndex` (0 is first) among the tags of `kind`
   * (every kind without it) and resolves to its new key. It reads the list and
   * calls `reorder` with the neighbours there.
   */
  move(input: {
    id: string;
    toIndex: number;
    kind?: string | undefined;
  }): AsyncResult<string>;
  delete(id: string): AsyncResult<boolean>;
  /** Puts a tag on `record`. */
  attach(input: { record: RecordRef; tagId: string }): AsyncResult<boolean>;
  /** Takes a tag off `record`. */
  detach(input: { record: RecordRef; tagId: string }): AsyncResult<boolean>;
  /**
   * The tenant's tags in rank order: every kind, the tags of `kind`, or the
   * tags on the record `on` names.
   */
  list(params?: ListTagsParams): AsyncResult<readonly Tag<F>[]>;
  /**
   * Makes `tagIds` the tags on the record: attaches the missing ones and
   * detaches the others, in that order. It stops at the first failure.
   */
  replace(input: {
    record: RecordRef;
    tagIds: readonly string[];
  }): AsyncResult<{ readonly attached: number; readonly detached: number }>;
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

/** `{ patch }` with the keys of `input` the SQL patch takes, or nothing. */
function patchOf(input: UpdateTagInput<object>): { patch?: object } {
  const entries = PATCH_KEYS.flatMap((key) =>
    input[key] === undefined ? [] : [[key, input[key]] as const],
  );

  return entries.length === 0 ? {} : { patch: Object.fromEntries(entries) };
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

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Tags<F> = {
    create: ({ kind, name, color, description, slug, fields: extra }) =>
      tenant().andThen((organizationId) =>
        fields
          .args(extra)
          .andThen((checked) =>
            call(
              "create_tag",
              {
                tenant: organizationId,
                kind,
                name,
                color: color ?? null,
                description: description ?? null,
                ...(slug === undefined ? {} : { slug }),
                fields: checked,
              },
              (value) => ({ ...tagOf(value), name }),
            ).andThen(fields.row),
          ),
      ),
    update: ({ id, patch }) =>
      fields
        .args(patch.fields)
        .andThen((checked) =>
          call(
            "update_tag",
            {
              tag_id: id,
              name: patch.name ?? null,
              ...patchOf(patch),
              fields: checked,
            },
            (value) => value === true,
          ),
        ),
    reorder: ({ id, neighbors }) => {
      const key = rankBetweenResult(neighbors);

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

      return call("rank_tag", { tag_id: id, rank: key.data }, () => key.data);
    },
    move: ({ id, toIndex, kind }) =>
      hooked.list(kind === undefined ? {} : { kind }).andThen((tags) => {
        const neighbors = neighborsForIndex(tags, id, toIndex);

        return neighbors.ok
          ? hooked.reorder({ id, neighbors: neighbors.data })
          : AsyncResult.err(neighbors.error);
      }),
    delete: (id) =>
      call("delete_tag", { tag_id: id }, (value) => value === true),
    attach: ({ record, tagId }) =>
      tenant().andThen((organizationId) =>
        call(
          "tag",
          {
            tenant: organizationId,
            subject_type: record.type,
            subject_id: record.id,
            tag_id: tagId,
          },
          (value) => value === true,
        ),
      ),
    detach: ({ record, tagId }) =>
      tenant().andThen((organizationId) =>
        call(
          "untag",
          {
            tenant: organizationId,
            subject_type: record.type,
            subject_id: record.id,
            tag_id: tagId,
          },
          (value) => value === true,
        ),
      ),
    list: (params = {}) =>
      tenant().andThen((organizationId) => {
        const { kind, on } = params;

        const listed =
          on === undefined
            ? call(
                "list_tags",
                { tenant: organizationId, kind: kind ?? null },
                tagsOf,
              )
            : call(
                "subject_tags",
                {
                  tenant: organizationId,
                  subject_type: on.type,
                  subject_id: on.id,
                },
                (value) =>
                  tagsOf(value).filter(
                    (tag) => kind === undefined || tag.kind === kind,
                  ),
              );

        return listed.andThen(fields.rows);
      }),
    replace: ({ record, tagIds }) =>
      AsyncResult.from(async () => {
        const current = await hooked.list({ on: record });

        if (!current.ok) {
          return current;
        }

        const have = new Set(current.data.map((tag) => tag.id));
        const want = new Set(tagIds);
        const toAttach = [...want].filter((id) => !have.has(id));
        const toDetach = [...have].filter((id) => !want.has(id));

        for (const tagId of toAttach) {
          const attached = await hooked.attach({ record, tagId });

          if (!attached.ok) {
            return attached;
          }
        }

        for (const tagId of toDetach) {
          const detached = await hooked.detach({ record, tagId });

          if (!detached.ok) {
            return detached;
          }
        }

        return ok({ attached: toAttach.length, detached: toDetach.length });
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Tags<F> = withBlockHooks(client, options.hooks, {
    block: "tags",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
