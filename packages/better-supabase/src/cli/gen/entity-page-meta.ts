import { posix } from "node:path";

import type { EntitySeedValue } from "../../list/index.ts";
import type { Field } from "./entity-page-ui.ts";
import type {
  EntityPageContext,
  EntityPageOutput,
  ResolvedEntityPage,
} from "./entity-pages.ts";

import { CliError } from "../core/errors.ts";
import { GENERATED_HEADER } from "./emit.ts";
import {
  entityFormFields,
  humanize,
  kindOf,
  literal,
  modulePath,
  withPage,
} from "./entity-page-ui.ts";
import { camelOf } from "./renamed-blocks.ts";
import { q, runtimeSubpath } from "./shared.ts";

/** The most demo rows one page may ask for; a larger load is a scale seed. */
const MAX_DEMO_ROWS = 500;

const DEFAULT_DEMO_ROWS = 10;

/** The first demo day; rows count forward from it so a run is repeatable. */
const BASE_DAY = Date.UTC(2026, 0, 5);

const DAY = 86_400_000;

export function seedValue(
  key: string,
  field: Field,
  index: number,
): EntitySeedValue {
  const kind = kindOf(field);

  switch (kind) {
    case "number": {
      const low = field.minimum ?? 0;
      const high = field.maximum ?? low + 99;

      return Math.min(high, low + index);
    }

    case "boolean": {
      return index % 2 === 0;
    }

    case "enum": {
      const values = field.kind === "enum" ? field.values : [];

      return values[index % Math.max(values.length, 1)] ?? null;
    }

    case "date": {
      return new Date(BASE_DAY + index * DAY).toISOString().slice(0, 10);
    }

    case "datetime": {
      return new Date(BASE_DAY + index * DAY).toISOString();
    }

    case "uuid": {
      return `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`;
    }

    case "text": {
      const text = `${humanize(key)} ${String(index + 1)}`;

      return field.maxLength === undefined
        ? text
        : text.slice(0, field.maxLength);
    }

    case "json": {
      return null;
    }

    default: {
      const unreachable: never = kind;

      return unreachable;
    }
  }
}

/**
 * The demo rows of a page: one per `seed.demo`, filled from the required fields
 * of the block's input schema that are columns of the table. The values come
 * from the field's kind and bounds, so the same descriptor gives the same
 * rows.
 */
export function entityPageSeedRows(
  entry: ResolvedEntityPage,
): readonly Readonly<Record<string, EntitySeedValue>>[] {
  const { seed } = entry.page;
  const { table } = entry;
  const fields = entry.schemas?.input?.fields;

  if (seed === undefined || table === undefined || fields === undefined) {
    return [];
  }

  const demo = seed.demo ?? DEFAULT_DEMO_ROWS;

  if (demo > MAX_DEMO_ROWS) {
    throw new CliError(
      "config_invalid",
      `gen.entityPages: ${entry.page.entity}: seed.demo is ${String(demo)}; the most is ${String(MAX_DEMO_ROWS)}. Use \`pnpm db:seed:scale\` for larger loads.`,
    );
  }

  const columns = Object.entries(fields).flatMap(([key, field]) => {
    const column = table.columns[key];

    return column === undefined ||
      field.optional === true ||
      field.readOnly === true ||
      kindOf(field) === "json"
      ? []
      : [{ key, column, field }];
  });

  return Array.from({ length: demo }, (_, index) =>
    Object.fromEntries(
      columns.map(({ key, column, field }) => [
        column,
        seedValue(key, field, index),
      ]),
    ),
  );
}

/**
 * `pages/<name>.seed.ts`: the demo rows of `page.seed`, keyed by database
 * column, with the table, the tenant column and the tiers. A page without
 * `seed`, or whose block exports no input schema, writes no file.
 */
export const SEED_OUTPUT: EntityPageOutput = {
  apiVersion: 1,
  id: "seed",
  render: (context) =>
    withPage(context, (entry) => {
      const { seed } = entry.page;
      const { table } = entry;

      if (seed === undefined || table === undefined) {
        return;
      }

      const rows = entityPageSeedRows(entry);

      if (rows.length === 0) {
        throw new CliError(
          "config_invalid",
          `gen.entityPages: ${entry.page.entity}: seed needs the block's input schema with columns of ${table.name}, and the block exports none that fit. Remove \`seed\`.`,
        );
      }

      const tiers = seed.tiers ?? ["demo"];

      return {
        path: modulePath(context, entry.name, "seed"),
        contents: [
          GENERATED_HEADER,
          `import type { EntitySeed } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          "",
          `/** The demo rows of \`${entry.page.entity}\` for ${tiers.join(", ")}. */`,
          `export const ${camelOf(entry.name)}Seed = {`,
          `  entity: ${q(entry.page.entity)},`,
          `  table: ${q(`${table.schema}.${table.name}`)},`,
          `  tenant: ${table.tenant === undefined ? "undefined" : q(table.tenant)},`,
          `  tiers: ${literal(tiers)},`,
          "  rows: [",
          ...rows.map((row) => `    ${literal(row)},`),
          "  ],",
          "} as const satisfies EntitySeed;",
          "",
        ].join("\n"),
      };
    }),
};

/** The `import` of a sibling generated module, without its extension. */
const sibling = (name: string, part: string): string => `./${name}.${part}`;

/**
 * `pages/<name>.navigation.ts`: the nav item of a page that sets `area`. It
 * reads the record link from `<name>Detail.href` and the title key from the
 * first of `<name>Columns`, so the app edits no nav file per page.
 */
export const NAVIGATION_OUTPUT: EntityPageOutput = {
  apiVersion: 1,
  id: "navigation",
  render: (context) =>
    withPage(context, (entry) => {
      const { area, columns, sections } = entry.page;

      if (area === undefined) {
        return;
      }

      const name = camelOf(entry.name);
      const hasColumns = columns !== undefined && columns.length > 0;
      const hasDetail = sections !== undefined;

      return {
        path: modulePath(context, entry.name, "navigation"),
        contents: [
          GENERATED_HEADER,
          `import type { EntityNavItem } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          ...(hasColumns
            ? [
                `import { ${name}Columns } from ${q(sibling(entry.name, "columns"))};`,
              ]
            : []),
          ...(hasDetail
            ? [
                `import { ${name}Detail } from ${q(sibling(entry.name, "detail"))};`,
              ]
            : []),
          "",
          `/** The nav item of \`${entry.page.entity}\` under the \`${area}\` area. */`,
          `export const ${name}Nav = {`,
          `  entity: ${q(entry.page.entity)},`,
          `  area: ${q(area)},`,
          `  label: ${q(humanize(entry.name))},`,
          `  href: ${q(entry.page.route.replace(/(.)\/$/, "$1"))},`,
          `  recordHref: ${hasDetail ? `${name}Detail.href` : "undefined"},`,
          `  titleKey: ${hasColumns ? `${name}Columns[0].key` : "undefined"},`,
          "} as const satisfies EntityNavItem;",
          "",
        ].join("\n"),
      };
    }),
};

/** The message keys of a page: `<name>.columns.<key>`, facets and form fields. */
export function entityPageMessageKeys(
  entry: ResolvedEntityPage,
): readonly string[] {
  const { name } = entry;

  const form = [entry.schemas?.input, entry.schemas?.change].flatMap(
    (schema) =>
      schema === undefined
        ? []
        : entityFormFields(schema).map(
            (field) => `${name}.fields.${field.name}`,
          ),
  );

  return [
    `${name}.title`,
    ...(entry.page.columns ?? []).map((key) => `${name}.columns.${key}`),
    ...entry.surface.facets.map((key) => `${name}.facets.${key}`),
    ...(entry.page.sections ?? []).map((id) => `${name}.sections.${id}`),
    ...new Set(form),
  ];
}

/**
 * `pages/routes.manifest.ts`: one entry per page with its list route, its API
 * route, its detail route and its message keys. One file for every page, so the
 * app reads one list instead of a hand-edited manifest. The detail route comes
 * from `<name>Detail.route`.
 */
export const MANIFEST_OUTPUT: EntityPageOutput = {
  apiVersion: 1,
  id: "manifest",
  render(context: EntityPageContext) {
    if (context.pages.length === 0) {
      return [];
    }

    const detailed = context.pages.filter(
      (entry) => entry.page.sections !== undefined,
    );

    return [
      {
        path: posix.join(context.pagesDir, "routes.manifest.ts"),
        contents: [
          GENERATED_HEADER,
          `import type { EntityRouteEntry } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          ...detailed.map(
            (entry) =>
              `import { ${camelOf(entry.name)}Detail } from ${q(sibling(entry.name, "detail"))};`,
          ),
          "",
          "/** Every entity page: its routes and the message keys it reads. */",
          "export const entityRoutes = [",
          ...context.pages.flatMap((entry) => [
            "  {",
            `    entity: ${q(entry.page.entity)},`,
            `    name: ${q(entry.name)},`,
            `    route: ${q(entry.page.route.replace(/(.)\/$/, "$1"))},`,
            `    api: ${q(`/api/${entry.name}/list`)},`,
            `    detail: ${entry.page.sections === undefined ? "undefined" : `${camelOf(entry.name)}Detail.route`},`,
            `    messageKeys: ${literal(entityPageMessageKeys(entry))},`,
            "  },",
          ]),
          "] as const satisfies readonly EntityRouteEntry[];",
          "",
        ].join("\n"),
      },
    ];
  },
};
