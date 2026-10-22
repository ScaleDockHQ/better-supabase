import type { PermissionSet } from "../blocks/access/permissions.ts";
import type { SectionData, SectionResult } from "../blocks/sections.ts";
import type { ValidationIssue } from "../core/errors.ts";
import type { FilterField } from "../list/filter-query.ts";
import type { ListParseOptions, ListSearchParams } from "../list/list-query.ts";
import type { SubjectRef } from "../schema/types.ts";
import type { FeatureBlocks, RecordCan, RecordFeature } from "./feature.ts";
import type { SectionName, SectionNamed } from "./sections.ts";

import { dbError } from "../core/errors.ts";
import { AsyncResult, ok } from "../core/result.ts";
import { recordCan, recordSubject } from "./feature.ts";
import { findSection } from "./sections.ts";

/**
 * How a section fills a list column: `count` is how many rows it has (the
 * section's `count`, one query for the page), `data` its rows (its `column`, or
 * one `load` per row in one wave).
 */
export type RecordListColumn = "count" | "data";

/** The value a section's column holds for one row. */
export type RecordListCell<
  B extends FeatureBlocks,
  S extends string,
  C extends RecordListColumn,
> = C extends "count" ? number : SectionData<SectionNamed<B, S>>;

/**
 * The list query a record list runs: a `defineListQuery` definition, or
 * anything that parses URL state and returns a page of rows.
 */
export interface RecordListQuery<
  Q,
  P extends { readonly items: readonly unknown[] },
> {
  parse(
    input: ListSearchParams | undefined,
    options?: ListParseOptions,
  ):
    | { readonly ok: true; readonly value: Q }
    | { readonly ok: false; readonly issues: readonly ValidationIssue[] };
  run(db: never, query: Q): AsyncResult<P>;
  filterFields(): FilterField[];
}

/** What `defineRecordList` takes besides the feature and the list query. */
export interface RecordListSpec<
  N extends string,
  Cols extends { readonly [K in N]?: RecordListColumn },
  Row,
> {
  /** The sections shown as list columns, and how each one fills its cell. */
  readonly columns?: Cols;
  /** The record id of a row. Default: its `id`. */
  readonly id?: (row: Row) => string;
}

/** One row of a record list with its section cells. */
export interface RecordListRow<Row, Cells> {
  readonly subject: SubjectRef;
  readonly row: Row;
  readonly cells: Cells;
}

/** The cells of one row, by section name, each one settled. */
export type RecordListCells<B extends FeatureBlocks, Cols> = {
  readonly [S in keyof Cols & string]: SectionResult<
    RecordListCell<B, S, Cols[S] & RecordListColumn>
  >;
};

/** What a record list's `load` returns. */
export interface RecordListPage<Q, P, Row, Cells, Can> {
  /** The parsed URL state, defaults filled in. */
  readonly query: Q;
  /** The page as the list query returned it: totals, cursor and facet counts. */
  readonly page: Omit<P, "items">;
  readonly rows: readonly RecordListRow<Row, Cells>[];
  /** The fields the list's filter tree may name, for ReUI Filters. */
  readonly filterFields: readonly FilterField[];
  /** What the caller may do on each section, for bulk actions and columns. */
  readonly can: Can;
}

/** Where a record list loads from. */
export interface RecordListSource {
  /** The repositories the list query runs against (`ctx.db`). */
  readonly db: object;
  /** The feature's block clients, keyed like its blocks. */
  readonly clients: object;
  /**
   * The caller's keys, for the `can` flags and hidden columns. `undefined`
   * allows every section and leaves RLS to decide.
   */
  readonly permissions?: PermissionSet | null;
}

/**
 * A subject's list page: the list query, the sections shown as columns, and the
 * feature that owns them.
 */
export interface RecordList<
  T extends string,
  B extends FeatureBlocks,
  N extends SectionName<B>,
  Q,
  P extends { readonly items: readonly unknown[] },
  Cols,
> {
  readonly feature: RecordFeature<T, B> & { readonly sections: readonly N[] };
  readonly list: RecordListQuery<Q, P>;
  readonly columns: Cols;
  /**
   * Parses the URL state, runs the list query, then fills every column for the
   * whole page in one wave. Fails with `validation` on bad URL state and with
   * the list query's error; a column that fails is settled in its cells.
   */
  load(
    source: RecordListSource,
    input: ListSearchParams | undefined,
    options?: ListParseOptions,
  ): AsyncResult<
    RecordListPage<
      Q,
      P,
      P["items"][number],
      RecordListCells<B, Cols>,
      RecordCan<B, N>
    >
  >;
}

/**
 * `subjectKey` from `core/block-subjects.ts`, the key `countSection` and
 * `column` results use. Inlined so the records entry doesn't load the block
 * helpers.
 */
function subjectKey(subject: SubjectRef): string {
  return `${subject.type}:${subject.id}`;
}

function rowId(row: unknown): string {
  const id =
    typeof row === "object" && row !== null && "id" in row ? row.id : undefined;

  return typeof id === "string" || typeof id === "number" ? String(id) : "";
}

type Column = AsyncResult<Readonly<Record<string, unknown>>>;

type Load = (
  client: unknown,
  subject: SubjectRef,
  options: unknown,
) => AsyncResult<unknown>;

function loadEach(
  load: Load,
  client: unknown,
  subjects: readonly SubjectRef[],
): Column {
  return AsyncResult.from(async () => {
    const results = await Promise.all(
      subjects.map(
        async (subject) =>
          [
            subjectKey(subject),
            await load(client, subject, undefined),
          ] as const,
      ),
    );

    const values: Record<string, unknown> = {};

    for (const [key, result] of results) {
      if (!result.ok) {
        return result;
      }

      values[key] = result.data;
    }

    return ok(values);
  });
}

function columnOf(
  blocks: FeatureBlocks,
  clients: object,
  name: string,
  mode: RecordListColumn,
  subjects: readonly SubjectRef[],
): Column {
  const found = findSection(blocks, name);

  // SAFETY: a read of one key of the built blocks.
  const client = (clients as Readonly<Record<string, unknown>>)[
    found?.key ?? ""
  ];

  if (found === undefined || client === undefined) {
    return AsyncResult.err(
      dbError("invalid_request", `Section "${name}" has no block client`),
    );
  }

  type Many = (client: unknown, subjects: readonly SubjectRef[]) => Column;

  // SAFETY: the section's hooks take the client its block's creator made.
  const count = found.section.count as Many | undefined;
  // SAFETY: as for `count`.
  const column = found.section.column as Many | undefined;
  // SAFETY: as for `count`; a column loads each row without options.
  const load = found.section.load as Load;

  if (mode === "count") {
    return count === undefined
      ? AsyncResult.err(
          dbError("unsupported", `Section "${name}" can't count rows`),
        )
      : count(client, subjects);
  }

  return column === undefined
    ? loadEach(load, client, subjects)
    : column(client, subjects);
}

/**
 * A subject's list page over the sections of its record feature: `load` parses
 * the URL state, runs the list query, and fills each section column for the
 * whole page (a comment count, the tags) in one wave, with the caller's `can`
 * flags.
 *
 * ```ts
 * export const customerRecordList = defineRecordList(
 *   customerFeature,
 *   customerList,
 *   { columns: { comments: "count", tags: "data" } },
 * );
 * ```
 */
export function defineRecordList<
  T extends string,
  B extends FeatureBlocks,
  N extends SectionName<B>,
  Q,
  P extends { readonly items: readonly unknown[] },
  const Cols extends { readonly [K in N]?: RecordListColumn } = Record<
    never,
    never
  >,
>(
  feature: RecordFeature<T, B> & { readonly sections: readonly N[] },
  list: RecordListQuery<Q, P>,
  spec: RecordListSpec<N, Cols, P["items"][number]> = {},
): RecordList<T, B, N, Q, P, Cols> {
  // SAFETY: without `columns` the list shows no section, which is `Cols` at its
  // default.
  const columns = spec.columns ?? ({} as Cols);
  const idOf = spec.id ?? rowId;

  const entries = Object.entries(columns).filter(
    (entry): entry is [string, RecordListColumn] => entry[1] !== undefined,
  );

  return {
    feature,
    list,
    columns,
    load(source, input, options) {
      const parsed = list.parse(input, options);

      if (!parsed.ok) {
        return AsyncResult.err(
          dbError("validation", "Invalid list state", {
            issues: parsed.issues,
          }),
        );
      }

      const can = recordCan(feature, source.permissions);
      // SAFETY: every entry of `RecordCan` has a `read` flag.
      const flags = can as Readonly<Record<string, { readonly read: boolean }>>;

      // SAFETY: the list query runs against the repositories the app passes.
      return list
        .run(source.db as never, parsed.value)
        .andThen(async (page) => {
          const { items, ...rest } = page;

          const listed = items.map((row) => ({
            row,
            subject: recordSubject(feature, idOf(row)),
          }));

          const subjects = listed.map((each) => each.subject);

          const cells = await Promise.all(
            entries.map(
              async ([name, mode]): Promise<
                readonly [
                  string,
                  RecordListColumn,
                  SectionResult<Readonly<Record<string, unknown>>>,
                ]
              > => {
                if (flags[name]?.read === false) {
                  return [name, mode, { kind: "hidden" }];
                }

                const result = await columnOf(
                  feature.blocks,
                  source.clients,
                  name,
                  mode,
                  subjects,
                );

                return [
                  name,
                  mode,
                  result.ok
                    ? { kind: "ok", data: result.data }
                    : { kind: "error", error: result.error },
                ];
              },
            ),
          );

          return AsyncResult.ok({
            query: parsed.value,
            page: rest,
            // SAFETY: one cell per column, holding the value its section gave
            // the row, as `RecordListCells` types them.
            rows: listed.map(({ row, subject }) => {
              const key = subjectKey(subject);

              return {
                subject,
                row,
                cells: Object.fromEntries(
                  cells.map(([name, mode, result]) => [
                    name,
                    result.kind === "ok"
                      ? {
                          kind: "ok",
                          data:
                            result.data[key] ??
                            (mode === "count" ? 0 : undefined),
                        }
                      : result,
                  ]),
                ),
              };
            }) as never,
            filterFields: list.filterFields(),
            can,
          });
        });
    },
  };
}
