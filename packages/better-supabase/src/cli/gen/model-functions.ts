import type { FunctionResult } from "../../index.ts";
import type { FunctionModel, ModelContext, TableModel } from "./model-types.ts";

import { CODEC_TYPE, applyCasing, codecFor, enumType } from "./model-types.ts";
import { arrayOf, configFor } from "./shared.ts";

/** The callable functions; warns about functions another schema shadows. */
export function buildFunctions(
  ctx: ModelContext,
  tableModels: readonly TableModel[],
): FunctionModel[] {
  const { config, catalog, enumsByName, tsType, warnings } = ctx;
  const tablesByName = new Map(
    tableModels.map((table) => [
      `${table.snapshot.schema}.${table.snapshot.name}`,
      table,
    ]),
  );
  // `$rpc` calls a function by its name, so one schema owns each name: the
  // first configured schema. Overloads in that schema stay, in signature order.
  const callable = catalog.functions
    .filter((fn) => config.schemas.includes(fn.schema))
    .filter((fn) => fn.returns !== "trigger" && fn.returns !== "event_trigger")
    .filter((fn) => !fn.args.some((arg) => arg.udt === "internal"));
  const ownerSchema = new Map<string, string>();
  for (const schema of config.schemas) {
    for (const fn of callable) {
      if (fn.schema === schema && !ownerSchema.has(fn.name)) {
        ownerSchema.set(fn.name, schema);
      }
    }
  }
  const shadowed = new Set<string>();
  const functions: FunctionModel[] = callable
    .filter((fn) => {
      if (ownerSchema.get(fn.name) === fn.schema) {
        return true;
      }
      shadowed.add(`${fn.schema}.${fn.name}`);
      return false;
    })
    .map((fn) => {
      const typeOf = (format: string, typeSchema?: string): string => {
        const isArray = format.startsWith("_");
        const values = enumsByName.get(
          `${typeSchema ?? fn.schema}.${isArray ? format.slice(1) : format}`,
        );
        if (values) {
          return isArray ? arrayOf(enumType(values)) : enumType(values);
        }
        return tsType(fn.schema, format, typeSchema);
      };
      const notNull = configFor(config.functions, fn.schema, fn.name)?.notNull;
      const notNullColumns = new Set(Array.isArray(notNull) ? notNull : []);
      if (Array.isArray(notNull)) {
        for (const name of notNullColumns) {
          if (!fn.returnsTable?.some((column) => column.name === name)) {
            throw new TypeError(
              `functions.${fn.name}.notNull: "${name}" is not a column the function returns`,
            );
          }
        }
      }
      const orNull = (type: string, column?: string): string =>
        notNull === true ||
        (column !== undefined && notNullColumns.has(column)) ||
        type === "undefined" ||
        type === "Json" ||
        type === "unknown"
          ? type
          : `${type} | null`;
      let returns: string;
      let result: FunctionResult | undefined;
      const rowTable = fn.returnsRelation
        ? tablesByName.get(fn.returnsRelation)
        : undefined;
      if (fn.returnsTable) {
        const columns = fn.returnsTable.map((column) => {
          const codec = codecFor(column.udt, config);
          return {
            db: column.name,
            app: applyCasing(column.name, config.casing),
            codec,
            tsType: codec
              ? CODEC_TYPE[codec]
              : typeOf(column.udt, column.typeSchema),
          };
        });
        returns = `{ ${columns
          .map(
            (column) =>
              `${JSON.stringify(column.app)}: ${orNull(column.tsType, column.db)}`,
          )
          .join("; ")} }[]`;
        if (
          columns.some(
            (column) => column.codec !== undefined || column.app !== column.db,
          )
        ) {
          result = {
            columns: columns.map(({ db, app, codec }) => ({
              db,
              ...(app === db ? {} : { name: app }),
              ...(codec ? { codec } : {}),
            })),
          };
        }
      } else if (rowTable) {
        returns = `Models[${JSON.stringify(rowTable.key)}]['Row']`;
        returns = fn.returnsSet ? arrayOf(returns) : orNull(returns);
        if (
          rowTable.columns.some(
            (column) => column.codec !== undefined || column.app !== column.db,
          )
        ) {
          result = { table: rowTable.key };
        }
      } else {
        returns = orNull(typeOf(fn.returns, fn.returnsSchema));
        if (fn.returnsSet) {
          returns = arrayOf(returns);
        }
      }
      return {
        key: fn.name,
        meta: {
          name: fn.name,
          schema: fn.schema,
          args: fn.args.map((arg) => ({ name: arg.name, type: arg.udt })),
          returns: fn.returns,
          returnsSet: fn.returnsSet,
          volatility: fn.volatility,
          ...(result ? { result } : {}),
        },
        args: fn.args.map((arg) => ({
          name: arg.name,
          tsType: typeOf(arg.isArray ? `_${arg.udt}` : arg.udt, arg.typeSchema),
          optional: arg.hasDefault,
        })),
        returns,
      };
    });

  for (const name of Object.keys(config.functions)) {
    if (
      !functions.some(
        (fn) => fn.key === name || `${fn.meta.schema}.${fn.key}` === name,
      )
    ) {
      throw new TypeError(
        `functions.${name}: no function "${name}" in ${config.schemas.join(", ")}`,
      );
    }
  }
  for (const id of shadowed) {
    const name = id.slice(id.indexOf(".") + 1);
    warnings.push(
      `${id}: ${ownerSchema.get(name) ?? ""}.${name} has the same name and comes first in \`schemas\`, so ${id} gets no \`$rpc\` types.`,
    );
  }
  return functions;
}
