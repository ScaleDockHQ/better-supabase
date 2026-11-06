import type { BlockSqlContext } from "../context.ts";
import type {
  TemplateChildTable,
  TemplateContribution,
  TemplateRules,
} from "../contributions.ts";

import { isRecord } from "../../core/guards.ts";
import { uniqueContributions } from "../contributions.ts";

const TYPE = /^[a-z][a-z0-9_.-]{0,63}$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;
const TABLE = /^[a-z_][a-z0-9_]{0,62}(\.[a-z_][a-z0-9_]{0,62})?$/;
const CALL = /^[a-z_"][a-z0-9_".]*(\.[a-z_"][a-z0-9_"]*)+$/;

/** One template type, from the app's `options.types` or a block contribution. */
export interface TemplateType extends TemplateContribution {
  readonly idColumn: string;
}

/**
 * The template types in force: the app's `options.types`, then contributions
 * for types the app did not name. An empty registry keeps today's free-form
 * types.
 */
export function templateTypes(ctx: BlockSqlContext): readonly TemplateType[] {
  const configured = configuredTypes(ctx);
  const named = new Set(configured.map((item) => item.type));

  const contributed = uniqueContributions(
    "templates",
    ctx.contributions("templates"),
    (item) => item.type,
  )
    .filter((item) => !named.has(item.type))
    .map((item) => normalize("contributes.templates", item));

  return [...configured, ...contributed];
}

function configuredTypes(ctx: BlockSqlContext): readonly TemplateType[] {
  const raw = ctx.option("types");

  if (raw === undefined) {
    return [];
  }

  if (!isRecord(raw)) {
    throw new TypeError("blocks.templates.options.types must be an object");
  }

  return Object.entries(raw).map(([type, entry]) => {
    if (!isRecord(entry)) {
      throw new TypeError(
        `blocks.templates.options.types.${type} must be an object`,
      );
    }

    return normalize(`blocks.templates.options.types.${type}`, {
      type,
      ...entry,
    });
  });
}

function normalize(
  where: string,
  entry: { readonly type: string } & Partial<TemplateContribution>,
): TemplateType {
  if (!TYPE.test(entry.type)) {
    throw new TypeError(`${where}: "${entry.type}" is not a template type`);
  }

  if (entry.storage !== "body" && entry.storage !== "rows") {
    throw new TypeError(`${where}.storage must be "body" or "rows"`);
  }

  if (entry.storage === "rows") {
    if (entry.table === undefined || !TABLE.test(entry.table)) {
      throw new TypeError(`${where}.table must be "schema.table"`);
    }

    if (
      entry.templateColumn === undefined ||
      !COLUMN.test(entry.templateColumn)
    ) {
      throw new TypeError(`${where}.templateColumn must be a column name`);
    }

    if (entry.clone === undefined || !CALL.test(entry.clone)) {
      throw new TypeError(`${where}.clone must be a schema-qualified function`);
    }
  }

  const idColumn = entry.idColumn ?? "id";

  if (!COLUMN.test(idColumn)) {
    throw new TypeError(`${where}.idColumn must be a column name`);
  }

  if (entry.extension !== undefined && !TABLE.test(entry.extension)) {
    throw new TypeError(`${where}.extension must be "schema.table"`);
  }

  return {
    ...entry,
    type: entry.type,
    storage: entry.storage,
    idColumn,
    ...(entry.children === undefined
      ? {}
      : {
          children: entry.children.map((child, index) =>
            childOf(where, index, child),
          ),
        }),
    ...(entry.rules === undefined
      ? {}
      : { rules: rulesOf(where, entry.rules) }),
  };
}

function childOf(
  where: string,
  index: number,
  child: TemplateChildTable,
): TemplateChildTable {
  const at = `${where}.children[${String(index)}]`;

  if (!TABLE.test(child.table) || !COLUMN.test(child.parent)) {
    throw new TypeError(`${at} must be { table: "schema.table", parent }`);
  }

  return child;
}

function rulesOf(where: string, rules: TemplateRules): TemplateRules {
  for (const [index, date] of (rules.dates ?? []).entries()) {
    if (
      !COLUMN.test(date.column) ||
      !COLUMN.test(date.days) ||
      (date.from !== "now" && !COLUMN.test(date.from))
    ) {
      throw new TypeError(
        `${where}.rules.dates[${String(index)}] must name a column, "now" or a column, and a settings key`,
      );
    }
  }

  for (const name of rules.variables ?? []) {
    if (!COLUMN.test(name)) {
      throw new TypeError(`${where}.rules.variables must be column names`);
    }
  }

  return rules;
}
