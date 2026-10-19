import type { ValidationIssue } from "../../core/errors.ts";
import type {
  FilterField,
  FilterFieldInfo,
  FilterFieldLabels,
  FilterFieldType,
  FilterLimits,
  FilterQuery,
} from "../../list/filter-query.ts";

import {
  checkFilterQuery,
  FILTER_OPERATORS,
  toFilterFields,
} from "../../list/filter-query.ts";

/** One field of `defineRuleFields`: a value rules on the subject type may test. */
export interface RuleFieldDefinition {
  readonly type: FilterFieldType;
  readonly label?: string;
  readonly description?: string;
  /** The subject record key the value is read from, dotted for a nested value. Defaults to the field id. */
  readonly column?: string;
  /**
   * The Postgres type, which decides how dates compare: `date`, `timestamp`
   * or `timestamptz` (the default for date fields).
   */
  readonly columnType?: string;
  /** Whether the value may be missing, so "is not" also matches it. Default `true`. */
  readonly nullable?: boolean;
  /** Allowed values for `select` and `multiselect`. */
  readonly options?: readonly (
    | string
    | { readonly value: string; readonly label?: string }
  )[];
  /** A subset of the type's operators. */
  readonly operators?: readonly string[];
}

/** A catalog field as `rule_fields_list` returns it. */
export interface RuleField {
  readonly subjectType: string;
  readonly id: string;
  readonly label: string;
  readonly description: string | undefined;
  readonly type: FilterFieldType;
  readonly column: string;
  readonly columnType: string;
  readonly nullable: boolean;
  readonly options:
    | readonly { readonly value: string; readonly label: string }[]
    | undefined;
  readonly operators: readonly string[] | undefined;
}

/** The fields of one subject type, for `RulesAdmin.syncFields` and the editor. */
export interface RuleFieldCatalog<S extends string = string> {
  readonly subjectType: S;
  readonly fields: readonly RuleField[];
}

const DEFAULT_COLUMN_TYPE: Readonly<Record<FilterFieldType, string>> = {
  text: "text",
  number: "numeric",
  date: "timestamptz",
  select: "text",
  multiselect: "jsonb",
  boolean: "boolean",
  relation: "uuid",
};

const DATE_TYPES = new Set(["date", "timestamp", "timestamptz"]);
const SUBJECT_TYPE = /^[a-z][a-z0-9_]{0,62}$/;
const FIELD_ID = /^[A-Za-z_][A-Za-z0-9_]*(?:[.][A-Za-z_][A-Za-z0-9_]*)*$/;

function labelOf(id: string): string {
  const words = id
    .replaceAll(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replaceAll(/[_.-]+/g, " ")
    .trim()
    .toLowerCase();

  return words.charAt(0).toUpperCase() + words.slice(1);
}

/**
 * Declares the fields rules on `subjectType` may test. Sync the catalog with
 * `createRulesAdmin(...).syncFields(catalog)` so the database checks and
 * evaluates trees against the same fields.
 */
export function defineRuleFields<const S extends string>(
  subjectType: S,
  fields: Readonly<Record<string, RuleFieldDefinition>>,
): RuleFieldCatalog<S> {
  if (!SUBJECT_TYPE.test(subjectType)) {
    throw new TypeError(
      `defineRuleFields: "${subjectType}" is not a subject type (lowercase letters, digits and underscores)`,
    );
  }

  return {
    subjectType,
    fields: Object.entries(fields).map(([id, field]) => {
      const column = field.column ?? id;

      if (!FIELD_ID.test(id) || !FIELD_ID.test(column)) {
        throw new TypeError(
          `defineRuleFields(${subjectType}): "${id}" needs an id and column of dotted identifiers`,
        );
      }

      const allowed = new Set(
        FILTER_OPERATORS[field.type].map((entry) => entry.value),
      );

      const unknown = field.operators?.find((name) => !allowed.has(name));

      if (unknown !== undefined) {
        throw new TypeError(
          `defineRuleFields(${subjectType}.${id}): "${unknown}" is not a ${field.type} operator`,
        );
      }

      const columnType = field.columnType ?? DEFAULT_COLUMN_TYPE[field.type];

      if (field.type === "date" && !DATE_TYPES.has(columnType)) {
        throw new TypeError(
          `defineRuleFields(${subjectType}.${id}): a date field's columnType is date, timestamp or timestamptz`,
        );
      }

      return {
        subjectType,
        id,
        label: field.label ?? labelOf(id),
        description: field.description,
        type: field.type,
        column,
        columnType,
        nullable: field.nullable ?? true,
        options: field.options?.map((option) =>
          typeof option === "string"
            ? { value: option, label: labelOf(option) }
            : {
                value: option.value,
                label: option.label ?? labelOf(option.value),
              },
        ),
        operators: field.operators,
      };
    }),
  };
}

/** Catalog fields as list filter fields, for `evaluateFilterQuery` and `checkFilterQuery`. */
export function ruleFilterFieldInfo(
  fields: readonly RuleField[],
): FilterFieldInfo[] {
  return fields.map((field) => {
    const allowed = field.operators;

    return {
      id: field.id,
      type: field.type,
      column: field.column,
      columnMeta: {
        db: field.column,
        type: field.columnType,
        nullable: field.nullable,
        hasDefault: false,
      },
      label: field.label,
      ...(field.description === undefined
        ? {}
        : { description: field.description }),
      operators: FILTER_OPERATORS[field.type].filter(
        (entry) => allowed === undefined || allowed.includes(entry.value),
      ),
      ...(field.options === undefined ? {} : { options: field.options }),
    };
  });
}

/** The `fields` prop of ReUI's Filters for a rule editor. */
export function ruleFilterFields(
  fields: readonly RuleField[],
  labels?: FilterFieldLabels,
): FilterField[] {
  return toFilterFields(ruleFilterFieldInfo(fields), labels);
}

/** The defaults of `blocks.rules.options`. */
export const RULE_LIMITS: FilterLimits = {
  maxDepth: 4,
  maxRules: 50,
  maxValueLength: 10_000,
  maxValues: 100,
};

/**
 * The problems `save` would report for a tree, checked in the browser: an
 * empty list when the database will accept it. Unfinished conditions are
 * allowed; they take no part until they have an operator.
 */
export function checkRuleConditions(
  conditions: FilterQuery,
  fields: readonly RuleField[],
  limits: FilterLimits = RULE_LIMITS,
): readonly ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  checkFilterQuery(conditions, ruleFilterFieldInfo(fields), limits, issues);

  return issues;
}
