import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockSqlContext } from "../context.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { onSettings } from "../subjects.ts";

const KEY = /^[a-z][a-z0-9_-]{0,62}$/;
const FIELD = /^[a-z][a-z0-9_]{0,62}$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;
const BRAND = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$/;

/** An item a field's first option set starts with. */
export interface ItemTemplate {
  readonly key: string;
  readonly label: string;
  readonly level: number;
  readonly color?: string;
  readonly icon?: string;
}

/** One `on.<type>.<field>` entry, checked against `config.recordTypes`. */
export interface OptionBinding {
  readonly type: string;
  readonly subject: RegisteredSubject;
  readonly field: string;
  /** The record column the chosen item's level is written to. */
  readonly column: string;
  /** The record column that holds the chosen item. */
  readonly option: string;
  readonly min: number;
  readonly max: number;
  /** The record column that holds the scope of the set, when there is one. */
  readonly scope?: string;
  /** Writing the level column picks the first item at that level. */
  readonly follow: boolean;
  readonly items: readonly ItemTemplate[];
  /** Item templates per brand; a tenant of that brand starts with these. */
  readonly brands: Readonly<Record<string, readonly ItemTemplate[]>>;
}

function columnOf(where: string, value: unknown, fallback?: string): string {
  const column = value ?? fallback;

  if (typeof column !== "string" || !COLUMN.test(column)) {
    throw new TypeError(`${where} must be a column name`);
  }

  return column;
}

function levelOf(
  where: string,
  value: unknown,
  min: number,
  max: number,
): number {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < min ||
    value > max
  ) {
    throw new TypeError(
      `${where} must be an integer from ${String(min)} to ${String(max)}`,
    );
  }

  return value;
}

function itemsOf(
  where: string,
  value: unknown,
  min: number,
  max: number,
): readonly ItemTemplate[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new TypeError(`${where} must be a non-empty list`);
  }

  const keys = new Set<string>();

  return value.map((item: unknown, index): ItemTemplate => {
    const at = `${where}[${String(index)}]`;

    if (!isRecord(item)) {
      throw new TypeError(`${at} must be an object`);
    }

    const { key, label, level, color, icon } = item;

    if (typeof key !== "string" || !KEY.test(key) || keys.has(key)) {
      throw new TypeError(`${at}.key must be a distinct lowercase name`);
    }

    keys.add(key);

    if (typeof label !== "string" || label.length === 0) {
      throw new TypeError(`${at}.label is required`);
    }

    for (const [name, text] of [
      ["color", color],
      ["icon", icon],
    ] as const) {
      if (text !== undefined && (typeof text !== "string" || text === "")) {
        throw new TypeError(`${at}.${name} must be text`);
      }
    }

    return {
      key,
      label,
      level: levelOf(`${at}.level`, level, min, max),
      ...(typeof color === "string" && { color }),
      ...(typeof icon === "string" && { icon }),
    };
  });
}

/**
 * `on`, checked: one binding per subject type and field, next to the ones other
 * blocks contribute. An app's own entry merges over a contributed field.
 */
export function optionBindings(ctx: BlockSqlContext): readonly OptionBinding[] {
  const configured = onSettings(ctx);
  const raw: Record<string, Record<string, unknown>> = {};
  const builtInSubjects: Record<string, SubjectConfig> = {};

  const contributed = uniqueContributions(
    "option-sets",
    ctx.contributions("option-sets"),
    (each) => each.type,
  );

  const fieldsOf = (type: string, entry: unknown): Record<string, unknown> => {
    if (!isRecord(entry)) {
      throw new TypeError(
        `blocks.${ctx.instance}.on.${type} must map each field to a binding`,
      );
    }

    return entry;
  };

  for (const { type, table, tenant, fields } of contributed) {
    const own = fieldsOf(type, configured[type] ?? {});
    const merged: Record<string, unknown> = { ...own };

    for (const [field, entry] of Object.entries(fields)) {
      const mine = own[field];
      merged[field] = { ...entry, ...(isRecord(mine) ? mine : {}) };
    }

    raw[type] = merged;
    builtInSubjects[type] = { table, idType: "uuid", tenant };
  }

  for (const [type, entry] of Object.entries(configured)) {
    if (!(type in raw)) {
      raw[type] = fieldsOf(type, entry);
    }
  }

  const registry = registeredSubjects(
    { ...builtInSubjects, ...ctx.subjects },
    ctx.naming,
  );

  return Object.entries(raw).flatMap(([type, fields]) => {
    const subject = registry.find((item) => item.type === type);

    if (subject === undefined) {
      throw new TypeError(
        `blocks.${ctx.instance}.on.${type}: register "${type}" in config.recordTypes first`,
      );
    }

    if (subject.tenant === undefined) {
      throw new TypeError(
        `blocks.${ctx.instance}.on.${type}: config.recordTypes.${type} needs a tenant column`,
      );
    }

    return Object.entries(fields).map(([field, entry]): OptionBinding => {
      const where = `blocks.${ctx.instance}.on.${type}.${field}`;

      if (!FIELD.test(field) || !isRecord(entry)) {
        throw new TypeError(`${where} must be an object under a field name`);
      }

      const levels = entry["levels"];

      if (!isRecord(levels)) {
        throw new TypeError(`${where}.levels must be { min, max }`);
      }

      const min = levelOf(`${where}.levels.min`, levels["min"], 0, 32_000);
      const max = levelOf(`${where}.levels.max`, levels["max"], min, 32_000);
      const follow = entry["follow"];

      if (follow !== undefined && typeof follow !== "boolean") {
        throw new TypeError(`${where}.follow must be true or false`);
      }

      const column = columnOf(`${where}.column`, entry["column"], field);

      const brands = entry["brands"];

      if (brands !== undefined && !isRecord(brands)) {
        throw new TypeError(`${where}.brands must map a brand to its items`);
      }

      const scope = entry["scope"];

      return {
        type,
        subject,
        field,
        column,
        option: columnOf(
          `${where}.option`,
          entry["option"],
          `${column}_option_id`,
        ),
        min,
        max,
        follow: follow ?? false,
        items: itemsOf(`${where}.items`, entry["items"], min, max),
        brands: Object.fromEntries(
          Object.entries(brands ?? {}).map(([brand, items]) => {
            if (!BRAND.test(brand)) {
              throw new TypeError(`${where}.brands.${brand} is not a brand`);
            }

            return [
              brand,
              itemsOf(`${where}.brands.${brand}`, items, min, max),
            ];
          }),
        ),
        ...(scope !== undefined && {
          scope: columnOf(`${where}.scope`, scope),
        }),
      };
    });
  });
}

/**
 * `if subject_type = ... and field = ... then <branch> ... else <otherwise>`
 * over the bindings, as PL/pgSQL.
 */
export function byField(
  type: string,
  field: string,
  bindings: readonly OptionBinding[],
  branch: (binding: OptionBinding) => string,
  otherwise: string,
): string {
  if (bindings.length === 0) {
    return otherwise;
  }

  const arms = bindings.map(
    (binding, index) =>
      `    ${index === 0 ? "if" : "elsif"} ${type} = ${sqlString(binding.type)} and ${field} = ${sqlString(binding.field)} then\n${branch(binding)}`,
  );

  return `${arms.join("\n")}
    else
      ${otherwise}
    end if;`;
}

/** The values of a template list as SQL rows, with ranks from `ranks`. */
export function templateRows(
  items: readonly ItemTemplate[],
  ranks: readonly string[],
): string {
  return items
    .map(
      (item, index) =>
        `(${sqlString(item.key)}, ${sqlString(item.label)}, ${String(item.level)}, ${item.color === undefined ? "null::text" : sqlString(item.color)}, ${item.icon === undefined ? "null::text" : sqlString(item.icon)}, ${sqlString(ranks[index] ?? "V")})`,
    )
    .join(",\n          ");
}
