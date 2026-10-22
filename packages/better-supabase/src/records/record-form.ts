import type { EntitySchema } from "../blocks/entity-schema.ts";
import type { CustomFieldType } from "../core/contracts/field-formats.ts";
import type { FormFieldType } from "../core/contracts/form-definition.ts";
import type { FieldSpec } from "../core/table-schema.ts";

import { CUSTOM_FIELD_FORM_TYPES } from "../core/contracts/field-formats.ts";
import { optionalTemporal } from "../core/temporal.ts";

/** The input a field renders: a forms block field type, or a date and time. */
export type RecordFormInput = FormFieldType | "datetime";

/** One field of an entity form, in render order. */
export interface RecordFormField {
  /** The input key, or the custom field key. */
  readonly key: string;
  readonly label: string;
  readonly input: RecordFormInput;
  readonly required: boolean;
  /** `entity` for the block's input, `custom` for the tenant's custom fields. */
  readonly source: "entity" | "custom";
  readonly description?: string;
  /** The values an `option` or `multi` field offers. */
  readonly options?: readonly string[];
  readonly minimum?: number;
  readonly maximum?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
  /** A custom field marked sensitive. */
  readonly sensitive?: boolean;
}

/** A custom field definition; `customFields.listDefinitions(entity)` fits. */
export interface RecordFormCustomField {
  readonly key: string;
  readonly label: string;
  readonly type: string;
  readonly required: boolean;
  readonly sensitive?: boolean;
}

/** What a submitted form splits into: the block input and the custom values. */
export interface RecordFormValues<T> {
  readonly input: T;
  readonly custom: Readonly<Record<string, unknown>>;
}

export type RecordFormResult<T> =
  | ({ readonly ok: true } & RecordFormValues<T>)
  | {
      readonly ok: false;
      /** One message per field key; `""` for an issue not on one field. */
      readonly errors: Readonly<Record<string, string>>;
    };

export interface RecordForm<T> {
  readonly fields: readonly RecordFormField[];
  /** Checks the values with the entity schema and the custom fields' `required`. */
  validate(
    values: Readonly<Record<string, unknown>>,
  ): Promise<RecordFormResult<T>>;
}

export interface RecordFormOptions<T> {
  /**
   * The input keys to show, in order. Default: every key the schema accepts,
   * except read-only ones.
   */
  readonly fields?: readonly (keyof T & string)[];
  /** Labels by key. Default: the key in words (`dueAt` is `Due at`). */
  readonly labels?: Readonly<Partial<Record<string, string>>>;
  /** The tenant's custom fields for the entity, shown after the input fields. */
  readonly customFields?: readonly RecordFormCustomField[];
  /**
   * The zone a `datetime-local` value is read in for an instant field. Default:
   * `UTC`.
   */
  readonly timeZone?: string;
}

const INTEGER_TEXT = /^-?\d+$/;
const OFFSET = /(?:Z|[+-]\d{2}:\d{2})$/i;

const BOOLEAN_TEXT: Readonly<Record<string, boolean>> = {
  true: true,
  on: true,
  false: false,
};

function parsed<T>(read: () => T, raw: string): T | string {
  try {
    return read();
  } catch {
    return raw;
  }
}

/**
 * The value an input's text stands for, by the field's kind; text that doesn't
 * parse stays text, so the schema reports it.
 */
function coerce(spec: FieldSpec, value: string, timeZone: string): unknown {
  const temporal = optionalTemporal();

  switch (spec.kind) {
    case "integer":
    case "number": {
      const number = Number(value);

      return Number.isNaN(number) ? value : number;
    }

    case "bigint": {
      return INTEGER_TEXT.test(value) ? BigInt(value) : value;
    }

    case "boolean": {
      return BOOLEAN_TEXT[value] ?? value;
    }

    case "instant": {
      return temporal === undefined
        ? value
        : parsed(
            () =>
              OFFSET.test(value)
                ? temporal.Instant.from(value)
                : temporal.PlainDateTime.from(value)
                    .toZonedDateTime(timeZone)
                    .toInstant(),
            value,
          );
    }

    case "plainDate": {
      return temporal === undefined
        ? value
        : parsed(() => temporal.PlainDate.from(value), value);
    }

    case "plainDateTime": {
      return temporal === undefined
        ? value
        : parsed(() => temporal.PlainDateTime.from(value), value);
    }

    case "json": {
      return parsed((): unknown => JSON.parse(value), value);
    }

    case "uuid":
    case "string":
    case "datetime":
    case "date":
    case "enum":
    case "custom":
    case "unknown": {
      return value;
    }

    default: {
      const never: never = spec;

      return never;
    }
  }
}

/** `dueAt` and `due_at` are `Due at`. */
function labelOf(key: string): string {
  const words = key
    .replaceAll(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replaceAll("_", " ")
    .toLowerCase()
    .trim();

  return words.charAt(0).toUpperCase() + words.slice(1);
}

function inputOf(spec: FieldSpec): RecordFormInput {
  switch (spec.kind) {
    case "uuid":
    case "string": {
      return "text";
    }

    case "integer":
    case "bigint": {
      return "integer";
    }

    case "number": {
      return "number";
    }

    case "boolean": {
      return "bool";
    }

    case "date":
    case "plainDate": {
      return "date";
    }

    case "datetime":
    case "instant":
    case "plainDateTime": {
      return "datetime";
    }

    case "enum": {
      return spec.array === true ? "multi" : "option";
    }

    case "json":
    case "custom":
    case "unknown": {
      return "json";
    }

    default: {
      const never: never = spec;

      return never;
    }
  }
}

function entityField(
  key: string,
  spec: FieldSpec,
  label: string,
): RecordFormField {
  return {
    key,
    label,
    input: inputOf(spec),
    required: spec.optional !== true && spec.nullable !== true,
    source: "entity",
    ...(spec.description === undefined
      ? {}
      : { description: spec.description }),
    ...(spec.kind === "enum" ? { options: spec.values } : {}),
    ...(spec.minimum === undefined ? {} : { minimum: spec.minimum }),
    ...(spec.maximum === undefined ? {} : { maximum: spec.maximum }),
    ...(spec.minLength === undefined ? {} : { minLength: spec.minLength }),
    ...(spec.maxLength === undefined ? {} : { maxLength: spec.maxLength }),
  };
}

function isCustomFieldType(type: string): type is CustomFieldType {
  return Object.hasOwn(CUSTOM_FIELD_FORM_TYPES, type);
}

function customField(
  definition: RecordFormCustomField,
  label: string | undefined,
): RecordFormField {
  return {
    key: definition.key,
    label: label ?? definition.label,
    input: isCustomFieldType(definition.type)
      ? CUSTOM_FIELD_FORM_TYPES[definition.type]
      : "text",
    required: definition.required,
    source: "custom",
    ...(definition.sensitive === true ? { sensitive: true } : {}),
  };
}

function isBlank(value: unknown): boolean {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && value.trim() === "") ||
    (Array.isArray(value) && value.length === 0)
  );
}

/**
 * The fields of a form for one of a block's entities, from its input schema
 * (`block.schemas.<entity>.input`) and the tenant's custom fields. `validate`
 * runs the schema, so the form accepts what the block's `create` accepts.
 *
 * ```ts
 * const form = recordForm(tasksBlock.schemas.work_item.input, {
 *   fields: ["title", "body", "priority", "dueAt"],
 *   customFields: await customFields
 *     .listDefinitions("work_item")
 *     .orThrow(),
 * });
 * ```
 */
export function recordForm<T>(
  schema: EntitySchema<T>,
  options: RecordFormOptions<T> = {},
): RecordForm<T> {
  const specs = schema.spec.fields;

  const keys =
    options.fields ??
    Object.keys(specs).filter((key) => specs[key]?.readOnly !== true);

  const custom = options.customFields ?? [];
  const timeZone = options.timeZone ?? "UTC";

  const fields: RecordFormField[] = [
    ...keys.flatMap((key) => {
      const spec = specs[key];

      return spec === undefined
        ? []
        : [entityField(key, spec, options.labels?.[key] ?? labelOf(key))];
    }),
    ...custom.map((definition) =>
      customField(definition, options.labels?.[definition.key]),
    ),
  ];

  const entityKeys = new Set<string>(keys);
  const customKeys = new Set(custom.map((definition) => definition.key));

  return {
    fields,
    validate: async (values) => {
      const errors: Record<string, string> = {};
      const input: Record<string, unknown> = {};
      const customValues: Record<string, unknown> = {};

      for (const [key, value] of Object.entries(values)) {
        const spec = entityKeys.has(key) ? specs[key] : undefined;

        if (spec !== undefined && !isBlank(value)) {
          input[key] =
            typeof value === "string" && spec.array !== true
              ? coerce(spec, value.trim(), timeZone)
              : value;
        } else if (customKeys.has(key) && !isBlank(value)) {
          customValues[key] = value;
        }
      }

      for (const field of fields) {
        if (
          field.source === "custom" &&
          field.required &&
          isBlank(values[field.key])
        ) {
          errors[field.key] = `${field.label} is required`;
        }
      }

      const checked = await schema["~standard"].validate(input);

      if (checked.issues !== undefined) {
        for (const issue of checked.issues) {
          const first = issue.path?.[0];
          const part = typeof first === "object" ? first.key : first;
          const key = typeof part === "string" ? part : "";

          errors[key] ??= issue.message;
        }
      }

      if (Object.keys(errors).length > 0 || checked.issues !== undefined) {
        return { ok: false, errors };
      }

      return { ok: true, input: checked.value, custom: customValues };
    },
  };
}
