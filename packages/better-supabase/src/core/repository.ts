import type { TableMeta } from "../schema/types.ts";
import type { ExecuteResult } from "./executor.ts";

import { invalidRequest } from "../ir/build.ts";
import { decodeRows } from "../ir/codec.ts";
import { simplify } from "../ir/simplify.ts";
import {
  and,
  type Condition,
  type DeleteOp,
  type InsertOp,
  type Operation,
  type OrderTerm,
  type SelectColumn,
  type SelectOp,
  type Selection,
  type UpdateOp,
} from "../ir/types.ts";
import { encodeValue } from "../ir/wire.ts";
import { lookupOf } from "../schema/lookup.ts";
import { decodeBoundCursor, encodeBoundCursor, sortKey } from "./cursor.ts";
import { dbError } from "./errors.ts";
import { keysetCondition } from "./keyset.ts";
import { offsetEnvelope, pageWindow, strip } from "./paginate.ts";
import { AsyncResult, ok, toDbError, type Result } from "./result.ts";
import { byKey } from "./row-keys.ts";
import {
  type OperationRunner,
  optionsOf,
  signalOf,
  type Args,
} from "./runner.ts";
import { tuningOf } from "./timeout.ts";
import { countOf, maxAffectedOf } from "./write-args.ts";

const sensitiveByTable = new WeakMap<TableMeta, ReadonlySet<string>>();

const primaryOrders = new WeakMap<TableMeta, readonly OrderTerm[]>();

const existsSelections = new WeakMap<TableMeta, Selection>();

/** Database names of the table's `config.sensitive` columns. */
function sensitiveColumnsOf(table: TableMeta): ReadonlySet<string> {
  let sensitive = sensitiveByTable.get(table);

  if (!sensitive) {
    sensitive = new Set(
      lookupOf(table)
        .entries.filter(([, column]) => column.sensitive)
        .map(([, column]) => column.db),
    );
    sensitiveByTable.set(table, sensitive);
  }

  return sensitive;
}

/** Creates the runtime repository object for one table. */
export function createRepository(
  runner: OperationRunner,
  table: TableMeta,
): Record<string, unknown> {
  const { builder } = runner.runtime;
  const sensitiveDb = sensitiveColumnsOf(table);

  // A beforeMutation plugin (timestamps, actor) may fill an empty patch, so
  // only without one is an empty patch known to change nothing.
  const mutationHooks = runner.runtime.plugins.some(
    (plugin) => plugin.beforeMutation,
  );

  // SAFETY: the select option of every read method is a column list.
  const selection = (args: Args | undefined): Selection =>
    builder.selection(
      table,
      args?.["select"] as readonly string[] | undefined,
      args?.["include"],
    );

  const rowCount = (
    args: Args | undefined,
    name: "limit" | "offset",
  ): number | undefined => {
    const value = args?.[name];

    if (value === undefined) {
      return undefined;
    }

    if (
      typeof value !== "number" ||
      !Number.isSafeInteger(value) ||
      value < 0
    ) {
      invalidRequest(
        `"${name}" must be a non-negative integer, not ${String(value)}`,
        table.key,
      );
    }

    return value;
  };

  const selectOp = (
    args: Args | undefined,
    patch: Partial<SelectOp> = {},
  ): SelectOp => ({
    kind: "select",
    table,
    selection: selection(args),
    where: builder.where(table, args?.["where"]),
    orderBy: builder.orderBy(table, args?.["orderBy"]),
    limit: rowCount(args, "limit"),
    offset: rowCount(args, "offset"),
    count: undefined,
    head: false,
    single: undefined,
    ...patch,
  });

  /**
   * Writes return every column but the sensitive ones unless they are asked
   * for.
   */
  const returning = (args: Args | undefined): Selection | undefined => {
    if (args?.["returning"] === false) {
      return undefined;
    }

    const all = selection(args);

    if (args?.["select"] !== undefined || args?.["sensitive"] === true) {
      return all;
    }

    const columns = all.columns.filter(
      (entry) => !sensitiveDb.has(entry.column),
    );

    return columns.length === all.columns.length ? all : { ...all, columns };
  };

  const run = (
    op: Operation,
    args: Args | undefined,
  ): Promise<Result<ExecuteResult>> =>
    runner.run(op, optionsOf(args), signalOf(args), tuningOf(args));

  /** `primaryKey` holds app names; order terms take database names. */
  const defaultOrder = (): readonly OrderTerm[] => {
    let order = primaryOrders.get(table);

    if (!order) {
      order = table.primaryKey.map((name): OrderTerm => ({
        column: builder.column(table, name),
        direction: "asc",
        implicit: true,
      }));
      primaryOrders.set(table, order);
    }

    return order;
  };

  const notFound = <T>(): Result<T> =>
    runner.fail(table, dbError("not_found", `No ${table.key} row matched`));

  /**
   * Arguments the builder rejects fail like any other error: with the table and
   * an `error` event.
   */
  const guarded = <T>(work: () => Promise<Result<T>>): AsyncResult<T> =>
    AsyncResult.from(async () => {
      try {
        return await work();
      } catch (cause) {
        return runner.fail<T>(table, toDbError(cause));
      }
    });

  const base = {
    $tableName: table.key,
    $meta: table,

    findMany(args?: Args) {
      return guarded(async () => {
        const op = selectOp(args);

        const ordered =
          op.orderBy.length > 0 || table.primaryKey.length === 0
            ? op
            : { ...op, orderBy: defaultOrder() };

        const result = await run(ordered, args);

        return result.ok ? ok(result.data.rows) : result;
      });
    },

    findFirst(args?: Args) {
      return guarded(async () => {
        const result = await run(selectOp(args, { limit: 1 }), args);

        return result.ok ? ok(result.data.rows[0] ?? null) : result;
      });
    },

    findOnly(args: Args) {
      return guarded(async () => {
        const result = await run(
          selectOp(args, { limit: 2, unpaged: true }),
          args,
        );

        if (!result.ok) {
          return result;
        }

        if (result.data.rows.length > 1) {
          return runner.fail(
            table,
            dbError(
              "multiple_rows",
              `More than one ${table.key} row matched; findOnly expects at most one`,
            ),
          );
        }

        return ok(result.data.rows[0] ?? null);
      });
    },

    findUnique(args: Args) {
      return guarded(async () => {
        const op = selectOp(args, {
          where: builder.uniqueKey(table, args["where"]),
          limit: 1,
        });

        const result = await run(op, args);

        return result.ok ? ok(result.data.rows[0] ?? null) : result;
      });
    },

    findById(id: unknown, args?: Args) {
      return guarded(async () => {
        const op = selectOp(args, {
          where: builder.primaryKey(table, id),
          limit: 1,
        });

        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        const row = result.data.rows[0];

        return row ? ok(row) : notFound();
      });
    },

    count(args?: Args) {
      return guarded(async () => {
        const mode = args?.["mode"];

        const op = selectOp(
          { where: args?.["where"] },
          {
            selection: { columns: [], includes: [] },
            count: mode === "planned" || mode === "estimated" ? mode : "exact",
            head: true,
          },
        );

        const result = await run(op, args);

        return result.ok ? ok(result.data.count ?? 0) : result;
      });
    },

    aggregate(args: Args) {
      return guarded<unknown>(async () => {
        const aggregation = builder.aggregation(table, args);

        const orderBy = builder.aggregateOrderBy(
          table,
          args["orderBy"],
          aggregation,
        );

        const op = selectOp(
          {
            where: args["where"],
            limit: args["limit"],
            offset: args["offset"],
          },
          { selection: aggregation, orderBy },
        );

        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        if (args["groupBy"] !== undefined) {
          return ok(result.data.rows);
        }

        // Without groups the database returns one row, unless nothing can match.
        return ok(
          result.data.rows[0] ?? decodeRows(aggregation, [{}])[0] ?? {},
        );
      });
    },

    exists(args?: Args) {
      return guarded(async () => {
        const op = selectOp(
          { where: args?.["where"] },
          { selection: existsSelection(), limit: 1 },
        );

        const result = await run(op, args);

        return result.ok ? ok(result.data.rows.length > 0) : result;
      });
    },

    paginate(args: Args) {
      return guarded(async () =>
        "after" in args ? cursorPage(args) : offsetPage(args),
      );
    },

    create(data: unknown, args?: Args) {
      return guarded(async () => {
        const op = insertOp([data], args, undefined);
        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        return ok(
          args?.["returning"] === false ? null : (result.data.rows[0] ?? null),
        );
      });
    },

    createMany(rows: readonly unknown[], args?: Args) {
      return guarded(async () => {
        if (rows.length === 0) {
          return ok(args?.["returning"] === false ? { count: 0 } : []);
        }

        const result = await run(insertOp(rows, args, undefined), args);

        if (!result.ok) {
          return result;
        }

        return ok(
          args?.["returning"] === false
            ? { count: result.data.count ?? rows.length }
            : result.data.rows,
        );
      });
    },

    update(id: unknown, patch: unknown, args?: Args) {
      return guarded(async () => {
        const key = and(
          builder.primaryKey(table, id),
          builder.where(table, args?.["where"]),
        );

        const expect = args?.["expect"]
          ? builder.where(table, args["expect"])
          : undefined;

        const set = builder.row(table, patch, "update");
        const empty = !mutationHooks && Object.keys(set).length === 0;

        const op: UpdateOp = {
          kind: "update",
          table,
          set,
          where: and(key, expect),
          returning: returning(args),
        };

        // An empty patch changes nothing, so it reads the row instead of
        // sending an update the database rejects.
        const result = empty
          ? await run(
              selectOp(args, {
                where: and(key, expect),
                selection: op.returning ?? { columns: [], includes: [] },
                limit: 1,
                orderBy: [],
                offset: undefined,
              }),
              args,
            )
          : await run(op, args);

        if (!result.ok) {
          return result;
        }

        const affected =
          op.returning || empty
            ? result.data.rows.length
            : (result.data.count ?? 0);

        if (affected === 0) {
          if (!expect) {
            return notFound();
          }

          const exists = await run(
            selectOp(undefined, {
              where: key,
              selection: { columns: [], includes: [] },
              count: "exact",
              head: true,
            }),
            args,
          );

          if (exists.ok && (exists.data.count ?? 0) > 0) {
            return runner.fail(
              table,
              dbError(
                "stale",
                `The ${table.key} row changed since it was read`,
              ),
            );
          }

          return notFound();
        }

        return ok(op.returning ? (result.data.rows[0] ?? null) : null);
      });
    },

    updateMany(args: Args) {
      return guarded(async () => {
        const where = builder.where(table, args["where"]);

        if (simplify(where) === true && args["allowAll"] !== true) {
          return runner.fail(
            table,
            dbError(
              "invalid_request",
              'updateMany needs a "where" that filters rows; pass allowAll: true to update every row',
            ),
          );
        }

        const rows = args["returning"] === true;
        const bound = maxAffectedOf(args);

        if ("invalid" in bound) {
          return runner.fail(table, dbError("invalid_request", bound.invalid));
        }

        const set = builder.row(table, args["data"], "update");

        const op: UpdateOp = {
          kind: "update",
          table,
          set,
          where,
          returning: rows ? returning(args) : undefined,
          ...bound,
          ...countOf(args),
        };

        if (!mutationHooks && Object.keys(set).length === 0) {
          if (!rows) {
            return ok({ count: 0 });
          }

          const found = await run(
            selectOp(args, {
              where,
              selection: op.returning ?? selection(args),
            }),
            args,
          );

          return found.ok ? ok(found.data.rows) : found;
        }

        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        return ok(rows ? result.data.rows : { count: result.data.count ?? 0 });
      });
    },

    upsert(data: unknown, args?: Args) {
      return guarded(async () => {
        const op = insertOp(
          [data],
          args,
          conflictColumns(args?.["onConflict"]),
        );

        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        return ok(
          args?.["returning"] === false ? null : (result.data.rows[0] ?? null),
        );
      });
    },

    upsertMany(rows: readonly unknown[], args?: Args) {
      return guarded(async () => {
        if (rows.length === 0) {
          return ok(args?.["returning"] === false ? { count: 0 } : []);
        }

        const op = insertOp(rows, args, conflictColumns(args?.["onConflict"]));
        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        return ok(
          args?.["returning"] === false
            ? { count: result.data.count ?? rows.length }
            : result.data.rows,
        );
      });
    },

    delete(id: unknown, args?: Args) {
      return guarded(async () => {
        const op: DeleteOp = {
          kind: "delete",
          table,
          where: builder.primaryKey(table, id),
          returning: builder.selection(table, table.primaryKey, undefined),
        };

        const result = await run(op, args);

        if (!result.ok) {
          return result;
        }

        return (result.data.count ?? result.data.rows.length) === 0
          ? notFound()
          : ok(undefined);
      });
    },

    deleteMany(args: Args) {
      return guarded(async () => {
        const where = builder.where(table, args["where"]);

        if (!where || simplify(where) === true) {
          return runner.fail(
            table,
            dbError(
              "invalid_request",
              'deleteMany needs a "where" that filters rows',
            ),
          );
        }

        const rows = args["returning"] === true;
        const bound = maxAffectedOf(args);

        if ("invalid" in bound) {
          return runner.fail(table, dbError("invalid_request", bound.invalid));
        }

        const op: DeleteOp = {
          kind: "delete",
          table,
          where,
          returning: rows ? returning(args) : undefined,
          ...bound,
          ...countOf(args),
        };

        // Plugins that rewrite the delete (softDelete) read this to keep RETURNING.
        const result = await runner.run(
          op,
          rows ? { ...optionsOf(args), returning: true } : optionsOf(args),
          signalOf(args),
          tuningOf(args),
        );

        if (!result.ok) {
          return result;
        }

        return ok(rows ? result.data.rows : { count: result.data.count ?? 0 });
      });
    },
  };

  function insertOp(
    rows: readonly unknown[],
    args: Args | undefined,
    conflict: readonly string[] | undefined,
  ): InsertOp {
    const built = rows.map((row) => builder.row(table, row));

    return {
      kind: "insert",
      table,
      rows: conflict && built.length > 1 ? byKey(built, conflict) : built,
      returning: returning(args),
      onConflict: conflict
        ? {
            columns: conflict,
            action: args?.["ignoreDuplicates"] === true ? "ignore" : "update",
          }
        : undefined,
      defaultToNull: args?.["defaultToNull"] === true,
      ...countOf(args),
    };
  }

  /**
   * One column is enough to see a row: the primary key, or the first
   * non-sensitive column.
   */
  function existsSelection(): Selection {
    let found = existsSelections.get(table);

    if (!found) {
      const names = Object.keys(table.columns);

      const alias =
        table.primaryKey[0] ??
        names.find((name) => !table.columns[name]?.sensitive) ??
        names[0];

      const columns: SelectColumn[] =
        alias === undefined
          ? []
          : [{ alias, column: builder.column(table, alias) }];

      found = { columns, includes: [] };
      existsSelections.set(table, found);
    }

    return found;
  }

  function conflictColumns(target: unknown): readonly string[] {
    if (target === undefined || target === "primaryKey") {
      return table.primaryKey.map((name) => builder.column(table, name));
    }

    if (typeof target === "string") {
      const columns = table.uniqueKeys[target];

      if (!columns) {
        invalidRequest(
          `Unknown unique key "${target}" on "${table.key}"`,
          table.key,
        );
      }

      return columns.map((name) => builder.column(table, name));
    }

    if (Array.isArray(target)) {
      return target.map((name: unknown) => builder.column(table, String(name)));
    }

    return invalidRequest(`Invalid onConflict on "${table.key}"`, table.key);
  }

  async function offsetPage(args: Args): Promise<Result<unknown>> {
    const window = pageWindow(args);

    if ("invalid" in window) {
      return runner.fail(table, dbError("invalid_request", window.invalid));
    }

    const { size, offset } = window;

    const count =
      args["count"] ?? (args["withCount"] === true ? "exact" : undefined);

    const orderBy = builder.orderBy(table, args["orderBy"]);

    const op = selectOp(args, {
      orderBy:
        orderBy.length > 0 || table.primaryKey.length === 0
          ? orderBy
          : defaultOrder(),
      limit: size + 1,
      lookAhead: true,
      offset,
      count:
        count === "exact" || count === "planned" || count === "estimated"
          ? count
          : undefined,
    });

    const result = await run(op, args);

    if (!result.ok) {
      return result;
    }

    return ok(
      offsetEnvelope(result.data.rows, result.data.count, size, offset),
    );
  }

  async function cursorPage(args: Args): Promise<Result<unknown>> {
    const size = Number(args["size"]);

    if (!Number.isInteger(size) || size < 1) {
      return runner.fail(
        table,
        dbError("invalid_request", '"size" must be a positive integer'),
      );
    }

    const requested = builder.orderBy(table, args["orderBy"]);
    const related = requested.find((term) => term.relation);

    if (related) {
      return runner.fail(
        table,
        dbError(
          "invalid_request",
          `Cursor pages can't sort by the relation "${related.relation?.name}"; use an offset page`,
        ),
      );
    }

    const orderBy = withTieBreaker(requested);
    const base = selection(args);
    const { selection: withSort, added } = ensureColumns(base, orderBy);

    const sort = sortKey(
      `${table.key}|${orderBy.map((term) => `${term.column}.${term.direction}.${term.nulls ?? ""}`).join(",")}`,
    );

    let after: Condition | undefined;

    if (typeof args["after"] === "string") {
      const decoded = decodeBoundCursor(args["after"], sort);

      if ("invalid" in decoded && decoded.invalid === "sort") {
        return runner.fail(
          table,
          dbError(
            "invalid_request",
            "The cursor continues another orderBy; pass after: null to start the new order",
          ),
        );
      }

      const values = "values" in decoded ? decoded.values : undefined;

      if (!values || values.length !== orderBy.length) {
        return runner.fail(table, dbError("invalid_request", "Invalid cursor"));
      }

      const { byDb } = lookupOf(table);
      after = keysetCondition(
        orderBy,
        values,
        (name) => byDb.get(name)?.[1].nullable ?? true,
      );
    }

    const op = selectOp(args, {
      selection: withSort,
      where: and(builder.where(table, args["where"]), after),
      orderBy,
      limit: size + 1,
      lookAhead: true,
      offset: undefined,
      // Without a cursor the request matches every row, so its count is the total.
      count:
        args["withCount"] === true && after === undefined ? "exact" : undefined,
    });

    const result = await run(op, args);

    if (!result.ok) {
      return result;
    }

    let total = result.data.count;

    if (args["withCount"] === true && after !== undefined) {
      const counted = await run(
        selectOp(args, {
          selection: { columns: [], includes: [] },
          orderBy: [],
          limit: undefined,
          offset: undefined,
          count: "exact",
          head: true,
        }),
        args,
      );

      if (!counted.ok) {
        return counted;
      }

      total = counted.data.count;
    }

    const rows = result.data.rows.slice(0, size);
    const hasMore = result.data.rows.length > size;
    const last = rows.at(-1);

    const aliases = new Map(
      withSort.columns.map((entry) => [entry.column, entry.alias]),
    );

    const nextCursor =
      hasMore && last
        ? encodeBoundCursor(
            orderBy.map((term) =>
              encodeValue(last[aliases.get(term.column) ?? term.column]),
            ),
            sort,
          )
        : null;

    return ok({
      items: added.length > 0 ? rows.map((row) => strip(row, added)) : rows,
      nextCursor,
      hasMore,
      ...(args["withCount"] === true ? { total: total ?? 0 } : {}),
    });
  }

  function withTieBreaker(orderBy: readonly OrderTerm[]): OrderTerm[] {
    const terms = [...orderBy];

    for (const name of table.primaryKey) {
      const column = builder.column(table, name);

      if (!terms.some((term) => term.column === column)) {
        terms.push({ column, direction: terms[0]?.direction ?? "asc" });
      }
    }

    return terms;
  }

  function ensureColumns(
    base: Selection,
    orderBy: readonly OrderTerm[],
  ): { selection: Selection; added: string[] } {
    const columns = [...base.columns];
    const selected = new Set(columns.map((entry) => entry.column));
    const { byDb } = lookupOf(table);
    const added: string[] = [];

    for (const term of orderBy) {
      if (selected.has(term.column)) {
        continue;
      }

      const alias = byDb.get(term.column)?.[0];
      columns.push(
        alias === undefined
          ? { alias: term.column, column: term.column }
          : builder.selectColumn(table, alias),
      );
      selected.add(term.column);
      added.push(alias ?? term.column);
    }

    return { selection: { columns, includes: base.includes }, added };
  }

  return base;
}
