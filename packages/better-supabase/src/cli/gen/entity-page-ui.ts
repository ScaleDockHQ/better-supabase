import { posix } from "node:path";

import type { GeneratedFile } from "../../config/index.ts";
import type {
  EntityColumn,
  EntityFieldKind,
  EntityFormField,
} from "../../list/index.ts";
import type {
  EntityPageContext,
  EntityPageOutput,
  ResolvedEntityPage,
} from "./entity-pages.ts";

import { CliError } from "../core/errors.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { camelOf } from "./renamed-blocks.ts";
import { prop, q, runtimeSubpath } from "./shared.ts";

type InputSchema = NonNullable<
  NonNullable<ResolvedEntityPage["schemas"]>["input"]
>;

type Field = InputSchema["fields"][string];

const SECTION = /^[a-z][a-z0-9-]*$/;

const invalid = (message: string): CliError =>
  new CliError("config_invalid", `gen.entityPages: ${message}`);

/** `nextReviewOn` and `audit-log` as `Next review on` and `Audit log`. */
export function humanize(name: string): string {
  const words = name
    .replaceAll(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replaceAll(/[-_]+/g, " ")
    .toLowerCase();

  return words.charAt(0).toUpperCase() + words.slice(1);
}

function kindOf(field: Field): EntityFieldKind {
  switch (field.kind) {
    case "integer":
    case "number":
    case "bigint": {
      return "number";
    }

    case "boolean":
    case "uuid":
    case "enum": {
      return field.kind;
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

    case "json":
    case "custom": {
      return "json";
    }

    case "string":
    case "unknown": {
      return "text";
    }

    default: {
      const unreachable: never = field;

      return unreachable;
    }
  }
}

/** The kind of a column the input schema does not list, from its name. */
function kindByName(key: string): EntityFieldKind {
  if (key.endsWith("At")) {
    return "datetime";
  }

  if (key.endsWith("On")) {
    return "date";
  }

  if (key.endsWith("Id") || key === "id") {
    return "uuid";
  }

  return "text";
}

const schemaFields = (
  entry: ResolvedEntityPage,
): Readonly<Record<string, Field>> => ({
  ...entry.schemas?.change?.fields,
  ...entry.schemas?.input?.fields,
});

/** The columns of a page, in the order the descriptor lists them. */
export function entityPageColumns(
  entry: ResolvedEntityPage,
): readonly EntityColumn[] {
  const names = entry.page.columns ?? [];
  const fields = schemaFields(entry);

  return names.map((key): EntityColumn => {
    const column = entry.table?.columns[key];

    if (entry.table !== undefined && column === undefined) {
      throw invalid(
        `${entry.page.entity}: column "${key}" is not a column of ${entry.table.name}. Use ${Object.keys(entry.table.columns).join(", ")}.`,
      );
    }

    const field = fields[key];
    const values = field?.kind === "enum" ? field.values : undefined;
    const filter = entry.surface.filters.find((name) => name === key);
    const sort = entry.surface.sorts.find((name) => name === key);

    return {
      key,
      column: column ?? key,
      label: humanize(key),
      kind: field === undefined ? kindByName(key) : kindOf(field),
      ...(values === undefined ? {} : { values }),
      ...(sort === undefined ? {} : { sort }),
      ...(filter === undefined ? {} : { filter }),
    };
  });
}

/** The fields of a form from one input schema; read-only and `json` stay out. */
export function entityFormFields(
  schema: Pick<InputSchema, "title" | "fields">,
): readonly EntityFormField[] {
  return Object.entries(schema.fields)
    .filter(([, field]) => field.readOnly !== true && kindOf(field) !== "json")
    .map(([name, field]): EntityFormField => {
      const kind = kindOf(field);

      return {
        name,
        label: humanize(name),
        kind,
        optional: field.optional === true,
        nullable: field.nullable === true,
        ...(field.kind === "enum" ? { values: field.values } : {}),
        ...(field.minimum === undefined ? {} : { minimum: field.minimum }),
        ...(field.maximum === undefined ? {} : { maximum: field.maximum }),
        ...(field.minLength === undefined
          ? {}
          : { minLength: field.minLength }),
        ...(field.maxLength === undefined
          ? {}
          : { maxLength: field.maxLength }),
        ...(field.description === undefined
          ? {}
          : { description: field.description }),
      };
    });
}

/** A value as a TypeScript literal on one line. */
const literal = (value: unknown): string => {
  if (Array.isArray(value)) {
    return `[${value.map((item) => literal(item)).join(", ")}]`;
  }

  if (typeof value === "object" && value !== null) {
    return `{ ${Object.entries(value)
      .map(([key, item]) => `${prop(key)}: ${literal(item)}`)
      .join(", ")} }`;
  }

  return JSON.stringify(value);
};

const modulePath = (
  context: EntityPageContext,
  name: string,
  part: string,
): string => posix.join(context.pagesDir, `${name}.${part}.ts`);

const withPage = (
  context: EntityPageContext,
  pick: (entry: ResolvedEntityPage) => GeneratedFile | undefined,
): readonly GeneratedFile[] =>
  context.pages.flatMap((entry) => {
    const file = pick(entry);

    return file === undefined ? [] : [file];
  });

/**
 * `pages/<name>.columns.ts`: the columns of `page.columns`, each with its
 * label, kind and the declared sort and filter that header selects. A page
 * without `columns` writes no file.
 */
export const COLUMNS_OUTPUT: EntityPageOutput = {
  apiVersion: 1,
  id: "columns",
  render: (context) =>
    withPage(context, (entry) => {
      if (entry.page.columns === undefined) {
        return;
      }

      const columns = entityPageColumns(entry);

      return {
        path: modulePath(context, entry.name, "columns"),
        contents: [
          GENERATED_HEADER,
          `import type { EntityColumn } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          "",
          `/** The columns of \`${entry.page.entity}\` (${entry.page.route}), in order. */`,
          `export const ${camelOf(entry.name)}Columns = [`,
          ...columns.map((column) => `  ${literal(column)},`),
          "] as const satisfies readonly EntityColumn[];",
          "",
        ].join("\n"),
      };
    }),
};

/**
 * `pages/<name>.detail.ts`: the frame of the record's page, with the sections
 * of `page.sections`. A page without `sections` writes no file.
 */
export const DETAIL_OUTPUT: EntityPageOutput = {
  apiVersion: 1,
  id: "detail",
  render: (context) =>
    withPage(context, (entry) => {
      const { sections } = entry.page;

      if (sections === undefined) {
        return;
      }

      for (const id of sections) {
        if (!SECTION.test(id)) {
          throw invalid(
            `${entry.page.entity}: section "${id}" must be lowercase words joined by "-".`,
          );
        }
      }

      if (new Set(sections).size !== sections.length) {
        throw invalid(`${entry.page.entity}: a section is listed twice.`);
      }

      const route = entry.page.route.replace(/\/$/, "");

      return {
        path: modulePath(context, entry.name, "detail"),
        contents: [
          GENERATED_HEADER,
          `import type { EntityDetail } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          "",
          `/** The detail frame of \`${entry.page.entity}\`: ${route}/:id with its sections. */`,
          `export const ${camelOf(entry.name)}Detail = {`,
          `  entity: ${q(entry.page.entity)},`,
          `  route: ${q(`${route}/:id`)},`,
          "  sections: [",
          ...sections.map(
            (id) => `    { id: ${q(id)}, label: ${q(humanize(id))} },`,
          ),
          "  ],",
          `  href: (id) => \`${route}/\${id}\`,`,
          "} as const satisfies EntityDetail;",
          "",
        ].join("\n"),
      };
    }),
};

/**
 * `pages/<name>.form.ts`: a create form and an edit form over the input schemas
 * the block's actions validate. An entity whose block exports no input schema
 * writes no file.
 */
export const FORM_OUTPUT: EntityPageOutput = {
  apiVersion: 1,
  id: "forms",
  render: (context) =>
    withPage(context, (entry) => {
      const { input, change } = entry.schemas ?? {};

      if (input === undefined && change === undefined) {
        return;
      }

      const name = camelOf(entry.name);

      const forms = [
        ["Create", input] as const,
        ["Edit", change] as const,
      ].flatMap(([label, schema]) =>
        schema === undefined
          ? []
          : [
              `/** The ${label.toLowerCase()} form of \`${entry.page.entity}\`, from \`${schema.title}\`. */`,
              `export const ${name}${label}Form = defineEntityForm({`,
              `  entity: ${q(entry.page.entity)},`,
              "  fields: [",
              ...entityFormFields(schema).map(
                (field) => `    ${literal(field)},`,
              ),
              "  ],",
              "});",
              "",
            ],
      );

      return {
        path: modulePath(context, entry.name, "form"),
        contents: [
          GENERATED_HEADER,
          `import { defineEntityForm } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          "",
          ...forms,
        ].join("\n"),
      };
    }),
};
