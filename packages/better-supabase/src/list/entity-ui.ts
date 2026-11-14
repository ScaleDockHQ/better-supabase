import type { ValidationIssue } from "../core/errors.ts";

/** What a generated column or form field holds, from the entity's schema. */
export type EntityFieldKind =
  | "text"
  | "number"
  | "boolean"
  | "date"
  | "datetime"
  | "uuid"
  | "enum"
  | "json";

/** One column of an entity page's list, as `gen` writes it (ADR 0869). */
export interface EntityColumn {
  /** The logical column, in the casing of the row (`nextReviewOn`). */
  readonly key: string;
  /** The column's name in the database (`next_review_on`). */
  readonly column: string;
  /** A readable header (`Next review on`). */
  readonly label: string;
  readonly kind: EntityFieldKind;
  /** The values of an `enum` column, when the entity's schema lists them. */
  readonly values?: readonly string[];
  /** The declared sort this column's header selects, when the entity has one. */
  readonly sort?: string;
  /** The declared facet or filter that narrows by this column. */
  readonly filter?: string;
}

/** One section of an entity's detail page. */
export interface EntityDetailSection {
  /** The id for the tab or anchor (`audit-log`). */
  readonly id: string;
  /** A readable title (`Audit log`). */
  readonly label: string;
}

/** The frame of an entity's detail page, as `gen` writes it. */
export interface EntityDetail {
  readonly entity: string;
  /** The detail route, `<route>/:id`. */
  readonly route: string;
  readonly sections: readonly EntityDetailSection[];
  /** The href of one record's detail page. */
  href(id: string): string;
}

/** One field of a generated form, from the input schema the action validates. */
export interface EntityFormField {
  readonly name: string;
  readonly label: string;
  readonly kind: EntityFieldKind;
  /** The key may be left out. */
  readonly optional: boolean;
  /** An empty input means `null`. */
  readonly nullable: boolean;
  readonly values?: readonly string[];
  readonly minimum?: number;
  readonly maximum?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
  readonly description?: string;
}

/** The form's input, or what is wrong with it. */
export type EntityFormParse =
  | { readonly ok: true; readonly value: Record<string, unknown> }
  | { readonly ok: false; readonly issues: readonly ValidationIssue[] };

/** A form over the fields of one input schema. */
export interface EntityForm {
  readonly entity: string;
  readonly fields: readonly EntityFormField[];
  /**
   * Reads `FormData` or a record of text into the input the action takes.
   * Numbers and booleans are converted, an empty optional field is left out and
   * an empty nullable field is `null`. The action's own schema stays the
   * authority: this check only names the field a user can fix.
   */
  parse(input: FormData | Readonly<Record<string, unknown>>): EntityFormParse;
}

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

function textOf(
  input: FormData | Readonly<Record<string, unknown>>,
  name: string,
): string | undefined {
  const raw = input instanceof FormData ? input.get(name) : input[name];

  if (raw === undefined || raw === null) {
    return undefined;
  }

  return typeof raw === "string" ? raw : String(raw);
}

function convert(
  field: EntityFormField,
  text: string,
): { readonly value: unknown } | { readonly message: string } {
  switch (field.kind) {
    case "number": {
      const value = Number(text);

      if (!Number.isFinite(value)) {
        return { message: `${field.label} must be a number.` };
      }

      if (field.minimum !== undefined && value < field.minimum) {
        return { message: `${field.label} must be at least ${field.minimum}.` };
      }

      if (field.maximum !== undefined && value > field.maximum) {
        return { message: `${field.label} must be at most ${field.maximum}.` };
      }

      return { value };
    }

    case "enum": {
      return field.values?.includes(text) === false
        ? {
            message: `${field.label} must be one of ${field.values.join(", ")}.`,
          }
        : { value: text };
    }

    case "uuid": {
      return UUID.test(text)
        ? { value: text }
        : { message: `${field.label} must be an id.` };
    }

    case "json": {
      try {
        // SAFETY: `JSON.parse` returns `any`; the value is passed on unchecked.
        return { value: JSON.parse(text) as unknown };
      } catch {
        return { message: `${field.label} must be valid JSON.` };
      }
    }

    case "text":
    case "date":
    case "datetime": {
      if (field.minLength !== undefined && text.length < field.minLength) {
        return {
          message: `${field.label} needs at least ${field.minLength} characters.`,
        };
      }

      if (field.maxLength !== undefined && text.length > field.maxLength) {
        return {
          message: `${field.label} takes at most ${field.maxLength} characters.`,
        };
      }

      return { value: text };
    }

    case "boolean": {
      return { value: ["1", "on", "true"].includes(text) };
    }

    default: {
      const unreachable: never = field.kind;

      return unreachable;
    }
  }
}

/**
 * The form of one entity input. `gen` writes a call per entity page, with the
 * fields read from the block's input schema, so the form cannot drift from the
 * action it submits to (ADR 0869).
 */
export function defineEntityForm(options: {
  readonly entity: string;
  readonly fields: readonly EntityFormField[];
}): EntityForm {
  return {
    entity: options.entity,
    fields: options.fields,
    parse(input) {
      const issues: ValidationIssue[] = [];
      const value: Record<string, unknown> = {};

      for (const field of options.fields) {
        const text = textOf(input, field.name)?.trim();

        if (field.kind === "boolean") {
          // An unchecked box is absent from `FormData`.
          value[field.name] = ["1", "on", "true"].includes(text ?? "");
          continue;
        }

        if (text === undefined || text === "") {
          if (field.nullable) {
            value[field.name] = null;
          } else if (!field.optional) {
            issues.push({
              message: `${field.label} is required.`,
              path: [field.name],
            });
          }

          continue;
        }

        const result = convert(field, text);

        if ("message" in result) {
          issues.push({ message: result.message, path: [field.name] });
        } else {
          value[field.name] = result.value;
        }
      }

      return issues.length > 0 ? { ok: false, issues } : { ok: true, value };
    },
  };
}
