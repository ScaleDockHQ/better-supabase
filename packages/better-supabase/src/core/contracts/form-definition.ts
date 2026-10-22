import { isRecord } from "../guards.ts";

/**
 * The forms block's definition format and the JSON Schema each published
 * version gets. The SQL module embeds `FORM_DEFINITION_SCHEMA` and builds the
 * same answer schema as `formSchema`, so the two can't drift.
 */

/** A JSON value in a definition or an answer. */
export type FormJson =
  | string
  | number
  | boolean
  | null
  | readonly FormJson[]
  | { readonly [key: string]: FormJson };

/** A JSON Schema document, as the generator writes it. */
export type FormJsonSchema = { readonly [key: string]: FormJson };

export type FormFieldType =
  | "text"
  | "textarea"
  | "email"
  | "url"
  | "number"
  | "integer"
  | "date"
  | "bool"
  | "consent"
  | "option"
  | "multi"
  | "json"
  | "nps";

export const FORM_FIELD_TYPES: readonly FormFieldType[] = [
  "text",
  "textarea",
  "email",
  "url",
  "number",
  "integer",
  "date",
  "bool",
  "consent",
  "option",
  "multi",
  "json",
  "nps",
];

/** The field types that can't have a `correct` answer. */
export const UNSCORED_FIELD_TYPES: readonly FormFieldType[] = [
  "consent",
  "json",
  "nps",
];

/** The highest answer to an `nps` field; the lowest is 0. */
export const NPS_MAX = 10;

/**
 * When a step or field shows: an earlier field's answer `equals` a value, is
 * one of `in`, or is `filled` (present and not `null`, `""` or `[]`).
 */
export type FormCondition =
  | { readonly field: string; readonly equals: FormJson }
  | { readonly field: string; readonly in: readonly FormJson[] }
  | { readonly field: string; readonly filled: true };

export interface FormOption {
  readonly value: string;
  readonly label: string;
}

export interface FormField {
  /** The answer's key: a letter, then letters, digits or `_`. */
  readonly key: string;
  readonly label?: string;
  readonly type?: FormFieldType;
  readonly required?: boolean;
  readonly help?: string;
  readonly placeholder?: string;
  /** The choices of an `option` or `multi` field. */
  readonly options?: readonly FormOption[];
  /** The bounds of a number, or the number of choices of a `multi` field. */
  readonly min?: number;
  readonly max?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
  readonly pattern?: string;
  readonly showIf?: FormCondition;
  /**
   * A custom-fields definition id. Publishing copies its label, type, options
   * and `required` into the field; the field's own keys win.
   */
  readonly customField?: string;
  /**
   * The answer that earns the field's points: a choice's value, an array of
   * values for `multi` (in any order), or the exact value of the other types.
   * Text compares without case and surrounding spaces. Publishing moves it to
   * an answer key respondents can't read.
   */
  readonly correct?: FormJson;
  /** What a correct answer earns. Default 1; needs `correct`. */
  readonly points?: number;
}

export interface FormStep {
  readonly key: string;
  readonly title?: string;
  readonly description?: string;
  readonly showIf?: FormCondition;
  readonly fields: readonly FormField[];
}

/** How a scored form grades a submission. */
export interface FormScoring {
  /**
   * The share of the points a submission needs to pass, from 0 to 100. Without
   * it a scored submission gets a score but no pass or fail.
   */
  readonly passMark?: number;
}

export interface FormDefinition {
  readonly steps: readonly FormStep[];
  /** Needs a field with a `correct` answer. */
  readonly scoring?: FormScoring;
}

/** The dialect every generated schema declares (`SPEC_PINS.jsonSchema`). */
export const FORM_SCHEMA_DIALECT =
  "https://json-schema.org/draft/2020-12/schema";

/** The longest answer a field takes when it sets no `maxLength`. */
export const FORM_MAX_LENGTH: {
  readonly text: number;
  readonly textarea: number;
  readonly email: number;
  readonly url: number;
} = { text: 500, textarea: 10_000, email: 320, url: 2000 };

const KEY = { type: "string", pattern: "^[a-z][a-zA-Z0-9_]{0,62}$" } as const;

const CONDITION = {
  type: "object",
  required: ["field"],
  minProperties: 2,
  maxProperties: 2,
  additionalProperties: false,
  properties: {
    field: KEY,
    equals: {},
    in: { type: "array", minItems: 1, maxItems: 500 },
    filled: { const: true },
  },
} as const;

const TEXT = (max: number) => ({ type: "string", maxLength: max }) as const;

/**
 * The shape of a definition. It uses only keywords whose meaning is the same in
 * drafts 7 and 2020-12, because pg_jsonschema validates by draft 7 rules.
 */
export const FORM_DEFINITION_SCHEMA: FormJsonSchema = {
  $schema: FORM_SCHEMA_DIALECT,
  type: "object",
  required: ["steps"],
  additionalProperties: false,
  properties: {
    steps: {
      type: "array",
      minItems: 1,
      maxItems: 50,
      items: {
        type: "object",
        required: ["key", "fields"],
        additionalProperties: false,
        properties: {
          key: KEY,
          title: TEXT(200),
          description: TEXT(2000),
          showIf: CONDITION,
          fields: {
            type: "array",
            minItems: 1,
            maxItems: 200,
            items: {
              type: "object",
              required: ["key"],
              additionalProperties: false,
              properties: {
                key: KEY,
                label: { type: "string", minLength: 1, maxLength: 200 },
                type: { enum: [...FORM_FIELD_TYPES] },
                required: { type: "boolean" },
                help: TEXT(1000),
                placeholder: TEXT(200),
                options: {
                  type: "array",
                  minItems: 1,
                  maxItems: 500,
                  items: {
                    type: "object",
                    required: ["value", "label"],
                    additionalProperties: false,
                    properties: {
                      value: { type: "string", minLength: 1, maxLength: 200 },
                      label: { type: "string", minLength: 1, maxLength: 200 },
                    },
                  },
                },
                min: { type: "number" },
                max: { type: "number" },
                minLength: { type: "integer", minimum: 0 },
                maxLength: { type: "integer", minimum: 1 },
                pattern: TEXT(500),
                showIf: CONDITION,
                customField: {
                  type: "string",
                  pattern:
                    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
                },
                correct: {},
                points: { type: "number", minimum: 0, maximum: 10_000 },
              },
            },
          },
        },
      },
    },
    scoring: {
      type: "object",
      additionalProperties: false,
      properties: { passMark: { type: "number", minimum: 0, maximum: 100 } },
    },
  },
};

const EMPTY_VALUES: readonly FormJson[] = [null, "", []];

/** The schema a condition holds under, as an `if`. */
export function conditionSchema(condition: FormCondition): FormJsonSchema {
  const { field } = condition;

  const value: FormJson =
    "equals" in condition
      ? { const: condition.equals }
      : "in" in condition
        ? { enum: [...condition.in] }
        : { not: { enum: [...EMPTY_VALUES] } };

  return { properties: { [field]: value }, required: [field] };
}

const defined = (
  entries: Readonly<Record<string, FormJson | undefined>>,
): Record<string, FormJson> =>
  Object.fromEntries(
    Object.entries(entries).filter(
      (entry): entry is [string, FormJson] => entry[1] !== undefined,
    ),
  );

/** The schema of one field's answer. */
export function fieldSchema(field: FormField): FormJsonSchema {
  const type = field.type;

  if (type === undefined) {
    throw new TypeError(
      `form field ${field.key} has no type: publish the version to resolve its customField`,
    );
  }

  const values = (field.options ?? []).map((option) => option.value);
  const annotations = defined({ title: field.label, description: field.help });
  const maxLength = (fallback: number): number => field.maxLength ?? fallback;
  // `required` only asks for the key, so an empty answer needs its own floor.
  const floor = field.required === true ? 1 : undefined;

  switch (type) {
    case "text":
    case "textarea": {
      return {
        type: "string",
        maxLength: maxLength(FORM_MAX_LENGTH[type]),
        ...defined({
          minLength: field.minLength ?? floor,
          pattern: field.pattern,
        }),
        ...annotations,
      };
    }

    case "email": {
      return {
        type: "string",
        format: "email",
        maxLength: FORM_MAX_LENGTH.email,
        ...annotations,
      };
    }

    case "url": {
      return {
        type: "string",
        format: "uri",
        maxLength: FORM_MAX_LENGTH.url,
        ...annotations,
      };
    }

    case "number":
    case "integer": {
      return {
        type,
        ...defined({ minimum: field.min, maximum: field.max }),
        ...annotations,
      };
    }

    case "date": {
      return { type: "string", format: "date", ...annotations };
    }

    case "bool": {
      return { type: "boolean", ...annotations };
    }

    case "consent": {
      return { type: "boolean", const: true, ...annotations };
    }

    case "option": {
      return { type: "string", enum: values, ...annotations };
    }

    case "multi": {
      return {
        type: "array",
        items: { type: "string", enum: values },
        uniqueItems: true,
        ...defined({ minItems: field.min ?? floor, maxItems: field.max }),
        ...annotations,
      };
    }

    case "json": {
      return { ...annotations };
    }

    case "nps": {
      return { type: "integer", minimum: 0, maximum: NPS_MAX, ...annotations };
    }

    default: {
      const unknown: never = type;
      throw new TypeError(`unknown form field type ${String(unknown)}`);
    }
  }
}

/**
 * The JSON Schema 2020-12 a version's submissions validate against. A required
 * field with a `showIf` (its own or its step's) is required only while the
 * condition holds. Like `FORM_DEFINITION_SCHEMA`, it keeps to the keywords
 * drafts 7 and 2020-12 share.
 */
export function formSchema(definition: FormDefinition): FormJsonSchema {
  const properties: Record<string, FormJson> = {};
  const required: string[] = [];
  const conditional: FormJson[] = [];

  for (const step of definition.steps) {
    for (const field of step.fields) {
      properties[field.key] = fieldSchema(field);

      if (field.required !== true) {
        continue;
      }

      const conditions = [step.showIf, field.showIf]
        .filter((condition) => condition !== undefined)
        .map(conditionSchema);

      if (conditions.length === 0) {
        required.push(field.key);
        continue;
      }

      conditional.push({
        if: conditions.length === 1 ? conditions[0]! : { allOf: conditions },
        // oxlint-disable-next-line unicorn/no-thenable -- the JSON Schema keyword; the schema is serialized, never awaited
        then: { required: [field.key] },
      });
    }
  }

  return {
    $schema: FORM_SCHEMA_DIALECT,
    type: "object",
    properties,
    additionalProperties: false,
    ...(required.length > 0 ? { required } : {}),
    ...(conditional.length > 0 ? { allOf: conditional } : {}),
  };
}

/**
 * Whether `value` has a definition's outline: steps with a key and fields with
 * a key. `FORM_DEFINITION_SCHEMA` checks the rest.
 */
export function isFormDefinition(value: unknown): value is FormDefinition {
  return (
    isRecord(value) &&
    Array.isArray(value["steps"]) &&
    value["steps"].every(
      (step) =>
        isRecord(step) &&
        typeof step["key"] === "string" &&
        Array.isArray(step["fields"]) &&
        step["fields"].every(
          (field) => isRecord(field) && typeof field["key"] === "string",
        ),
    )
  );
}

/**
 * What the definition's shape can't say: duplicate keys, conditions on a field
 * that isn't earlier in the form, a field without a label and type (and no
 * `customField`), a choice field without options, and a `correct` answer the
 * field can't take (or `points` or `scoring` without one). Empty when the
 * definition is fine.
 */
export function formDefinitionProblems(
  definition: FormDefinition,
): readonly string[] {
  const problems: string[] = [];
  const steps = new Set<string>();
  const fields = new Set<string>();
  let scored = false;

  const refers = (condition: FormCondition | undefined, where: string) => {
    if (condition !== undefined && !fields.has(condition.field)) {
      problems.push(
        `${where}: showIf names ${condition.field}, which isn't an earlier field`,
      );
    }
  };

  for (const step of definition.steps) {
    if (steps.has(step.key)) {
      problems.push(`step ${step.key} is listed twice`);
    }

    steps.add(step.key);
    refers(step.showIf, `step ${step.key}`);

    for (const field of step.fields) {
      if (fields.has(field.key)) {
        problems.push(`field ${field.key} is listed twice`);
      }

      refers(field.showIf, `field ${field.key}`);
      fields.add(field.key);

      if (
        field.customField === undefined &&
        (field.label === undefined || field.type === undefined)
      ) {
        problems.push(
          `field ${field.key} needs a label and a type, or a customField`,
        );
      }

      if (
        field.customField === undefined &&
        (field.type === "option" || field.type === "multi") &&
        (field.options?.length ?? 0) === 0
      ) {
        problems.push(`field ${field.key} needs options`);
      }

      problems.push(...scoringProblems(field));
      scored ||= field.correct !== undefined;
    }
  }

  if (definition.scoring !== undefined && !scored) {
    problems.push("scoring needs a field with a correct answer");
  }

  return problems;
}

/** Whether `correct` is an answer a field of `type` with these choices takes. */
function correctFits(
  type: FormFieldType,
  correct: FormJson,
  values: readonly string[],
): boolean {
  switch (type) {
    case "text":
    case "textarea":
    case "email":
    case "url":
    case "date": {
      return typeof correct === "string";
    }

    case "number": {
      return typeof correct === "number";
    }

    case "integer": {
      return typeof correct === "number" && Number.isInteger(correct);
    }

    case "bool": {
      return typeof correct === "boolean";
    }

    case "option": {
      return typeof correct === "string" && values.includes(correct);
    }

    case "multi": {
      return (
        Array.isArray(correct) &&
        correct.length > 0 &&
        correct.every(
          (value) => typeof value === "string" && values.includes(value),
        )
      );
    }

    case "consent":
    case "json":
    case "nps": {
      return false;
    }

    default: {
      const unknown: never = type;
      throw new TypeError(`unknown form field type ${String(unknown)}`);
    }
  }
}

/** A field's `correct` and `points` problems, as `form_resolve` reports them. */
function scoringProblems(field: FormField): readonly string[] {
  const { correct, type } = field;

  if (correct === undefined) {
    return field.points === undefined
      ? []
      : [`field ${field.key}: points need a correct answer`];
  }

  if (correct === null) {
    return [`field ${field.key}: correct can't be null`];
  }

  if (type === undefined) {
    return [];
  }

  if (UNSCORED_FIELD_TYPES.includes(type)) {
    return [`field ${field.key}: a ${type} field can't have a correct answer`];
  }

  const values = (field.options ?? []).map((option) => option.value);

  return correctFits(type, correct, values)
    ? []
    : [`field ${field.key}: correct isn't an answer the field takes`];
}
