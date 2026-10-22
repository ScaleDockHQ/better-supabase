import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { UndoCall, UndoToken } from "../undo/undo.ts";

import {
  blockFields,
  readAllFields,
  readFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { subjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { undoToken } from "../undo/undo.ts";

export interface LinkInput<F extends object = Record<never, never>> {
  /**
   * A kind, or its inverse name (`blocked_by` stores `blocks` from the other
   * end).
   */
  readonly kind: string;
  /** Data on the link, such as a Gantt dependency's `type` and `lag`. */
  readonly data?: Readonly<Record<string, unknown>>;
  /**
   * Values for the app's extra columns (`options.extraColumns`); left out keeps
   * the stored ones.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export type UnlinkInput = Pick<LinkInput, "kind">;

export interface LinkResult<F extends object = Record<never, never>> {
  readonly id: string;
  /** The stored kind; an inverse name resolves to its kind. */
  readonly kind: string;
  /**
   * The stored source, after an inverse name or a symmetric kind swapped the
   * ends.
   */
  readonly source: RecordRef;
  readonly target: RecordRef;
  /** `false` when the link existed; its data was updated if `data` was given. */
  readonly created: boolean;
  /** The target a one-target kind replaced. */
  readonly replaced: {
    readonly target: RecordRef;
    readonly data: Readonly<Record<string, unknown>>;
  } | null;
  readonly undo: UndoToken | null;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

export interface UnlinkResult {
  readonly removed: boolean;
  readonly undo: UndoToken | null;
}

export interface Relation<F extends object = Record<never, never>> {
  readonly id: string;
  /**
   * The kind as read from the subject's side: `blocked_by` for an incoming
   * `blocks`.
   */
  readonly kind: string;
  readonly direction: "out" | "in";
  readonly subject: RecordRef;
  readonly data: Readonly<Record<string, unknown>>;
  readonly createdAt: string;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

export interface RelationEdge<F extends object = Record<never, never>> {
  readonly id: string;
  readonly kind: string;
  readonly source: RecordRef;
  readonly target: RecordRef;
  readonly data: Readonly<Record<string, unknown>>;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

export interface RelationNode extends RecordRef {
  readonly depth: number;
}

export type RelationRollup = "count" | "sum" | "avg" | "min" | "max";

export interface RollupInput {
  readonly kind: string;
  /** The descendants' subject type whose table holds `column`. */
  readonly of: string;
  readonly agg: RelationRollup;
  /** Required for every aggregate except `count`. */
  readonly column?: string;
}

export interface RelationsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTenantOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * A Standard Schema for the extra columns of the relations table
   * (`blocks.relations.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Relations<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Every method acts in the block's `tenant`. */
export interface Relations<F extends object = Record<never, never>> {
  /** Links `source` to `target` with a kind. */
  link(
    source: RecordRef,
    target: RecordRef,
    input: LinkInput<F>,
  ): AsyncResult<LinkResult<F>>;
  unlink(
    source: RecordRef,
    target: RecordRef,
    input: UnlinkInput,
  ): AsyncResult<UnlinkResult>;
  /** A subject's links in both directions, optionally of one kind. */
  of(subject: RecordRef, kind?: string): AsyncResult<Relation<F>[]>;
  /** Every link of a kind in the tenant (up to 10,000), for a chart or a tree. */
  edges(kind: string): AsyncResult<RelationEdge<F>[]>;
  ancestors(subject: RecordRef, kind: string): AsyncResult<RelationNode[]>;
  descendants(subject: RecordRef, kind: string): AsyncResult<RelationNode[]>;
  /**
   * Aggregates a column over a subject's descendants, such as estimates under
   * an epic.
   */
  rollup(
    subject: RecordRef,
    input: RollupInput,
  ): AsyncResult<number | string | null>;
  /**
   * The id of the record of `intoType` that `origin` was already converted into
   * through a `created_from` link, or `undefined`. Check it before a conversion
   * so converting twice returns the first record.
   */
  convertedInto(
    origin: RecordRef,
    intoType: string,
  ): AsyncResult<string | undefined>;
  /**
   * The records a subject was converted from (`origins`, nearest first) and
   * into (`conversions`) through `created_from` links: a deal, its quote, the
   * order and the invoice.
   */
  lineage(
    subject: RecordRef,
  ): AsyncResult<{
    readonly origins: RelationNode[];
    readonly conversions: RelationNode[];
  }>;
}

const objectOf = (value: unknown): Readonly<Record<string, unknown>> =>
  isRecord(value) ? value : {};

const linkArgs = (
  organizationId: string,
  kind: string,
  source: RecordRef,
  target: RecordRef,
): Record<string, unknown> => ({
  tenant: organizationId,
  kind,
  source_type: source.type,
  source_id: source.id,
  target_type: target.type,
  target_id: target.id,
});

const walkArgs = (
  organizationId: string,
  kind: string,
  subject: RecordRef,
): Record<string, unknown> => ({
  tenant: organizationId,
  kind,
  subject_type: subject.type,
  subject_id: subject.id,
});

function edgeOf(value: unknown): RelationEdge {
  const row = recordOf(value, "relation");

  return {
    id: textOf(row["id"]),
    kind: textOf(row["kind"]),
    source: subjectRefOf(row["sourceType"], row["sourceId"]),
    target: subjectRefOf(row["targetType"], row["targetId"]),
    data: objectOf(row["data"]),
    fields: rowFields(row["fields"]),
  };
}

function nodeOf(value: unknown): RelationNode {
  const row = recordOf(value, "relation node");

  return {
    type: textOf(row["type"]),
    id: textOf(row["id"]),
    depth: typeof row["depth"] === "number" ? row["depth"] : 0,
  };
}

/** Relations over the `relations` module's functions, as the caller. */
export function createRelations<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: RelationsOptions<S>): Relations<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "relation fields");
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Relations<F> = {
    link: (source, target, input) =>
      tenant().andThen((organizationId) =>
        writeFields(fields, input.fields, (checked) =>
          call(
            "link",
            {
              ...linkArgs(organizationId, input.kind, source, target),
              data: input.data ?? null,
              fields: checked,
            },
            (value) => {
              const row = recordOf(value, "link");
              const kind = textOf(row["kind"]);
              const stored = subjectRefOf(row["sourceType"], row["sourceId"]);
              const to = subjectRefOf(row["targetType"], row["targetId"]);
              const created = row["created"] === true;
              const replacedRow = row["replaced"];

              const replaced = isRecord(replacedRow)
                ? {
                    target: subjectRefOf(
                      replacedRow["targetType"],
                      replacedRow["targetId"],
                    ),
                    data: objectOf(replacedRow["data"]),
                  }
                : null;

              const calls: UndoCall[] = [];
              const args = linkArgs(organizationId, kind, stored, to);

              if (created) {
                calls.push({ fn: "unlink", args });
              }

              if (replaced) {
                calls.push({
                  fn: "link",
                  args: {
                    ...linkArgs(organizationId, kind, stored, replaced.target),
                    data: replaced.data,
                  },
                });
              }

              const previous = row["previousData"];

              if (!created && input.data !== undefined && isRecord(previous)) {
                calls.push({ fn: "link", args: { ...args, data: previous } });
              }

              return {
                id: textOf(row["id"]),
                kind,
                source: stored,
                target: to,
                created,
                replaced,
                undo: calls.length > 0 ? undoToken(calls) : null,
                fields: rowFields(row["fields"]),
              };
            },
          ).andThen((result) => readFields(fields, result)),
        ),
      ),
    unlink: (source, target, input) =>
      tenant().andThen((organizationId) =>
        call(
          "unlink",
          linkArgs(organizationId, input.kind, source, target),
          (value) => {
            const row = recordOf(value, "unlink");
            const removed = row["removed"] === true;

            return {
              removed,
              undo: removed
                ? undoToken([
                    {
                      fn: "link",
                      args: {
                        ...linkArgs(organizationId, input.kind, source, target),
                        data: objectOf(row["data"]),
                      },
                    },
                  ])
                : null,
            };
          },
        ),
      ),
    of: (subject, kind) =>
      tenant().andThen((organizationId) =>
        call(
          "relations_of",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            kind: kind ?? null,
          },
          (value) =>
            recordsOf(value, "relations_of").map((row): Relation => ({
              id: textOf(row["id"]),
              kind: textOf(row["kind"]),
              direction: row["direction"] === "in" ? "in" : "out",
              subject: subjectRefOf(row["type"], row["subjectId"]),
              data: objectOf(row["data"]),
              createdAt: optionalText(row["createdAt"]) ?? "",
              fields: rowFields(row["fields"]),
            })),
        ).andThen((relations) => readAllFields(fields, relations)),
      ),
    edges: (kind) =>
      tenant().andThen((organizationId) =>
        call("relations_by_kind", { tenant: organizationId, kind }, (value) =>
          recordsOf(value, "relations_by_kind").map(edgeOf),
        ).andThen((edges) => readAllFields(fields, edges)),
      ),
    ancestors: (subject, kind) =>
      tenant().andThen((organizationId) =>
        call("ancestors", walkArgs(organizationId, kind, subject), (value) =>
          recordsOf(value, "ancestors").map(nodeOf),
        ),
      ),
    descendants: (subject, kind) =>
      tenant().andThen((organizationId) =>
        call("descendants", walkArgs(organizationId, kind, subject), (value) =>
          recordsOf(value, "descendants").map(nodeOf),
        ),
      ),
    convertedInto: (origin, intoType) =>
      tenant().andThen((organizationId) =>
        call(
          "converted_into",
          {
            tenant: organizationId,
            origin_type: origin.type,
            origin_id: origin.id,
            into_type: intoType,
          },
          (value) => (typeof value === "string" ? value : undefined),
        ),
      ),
    lineage: (subject) =>
      tenant().andThen((organizationId) => {
        const args = walkArgs(organizationId, "created_from", subject);

        return call("ancestors", args, (value) =>
          recordsOf(value, "ancestors").map(nodeOf),
        ).andThen((origins) =>
          call("descendants", args, (value) => ({
            origins,
            conversions: recordsOf(value, "descendants").map(nodeOf),
          })),
        );
      }),
    rollup: (subject, input) =>
      tenant().andThen((organizationId) =>
        call(
          "relation_rollup",
          {
            ...walkArgs(organizationId, input.kind, subject),
            of_type: input.of,
            column_name: input.column ?? null,
            agg: input.agg,
          },
          (value) =>
            typeof value === "number" || typeof value === "string"
              ? value
              : null,
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "relations",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
