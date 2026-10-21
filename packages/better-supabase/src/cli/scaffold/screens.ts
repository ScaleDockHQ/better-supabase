import { posix } from "node:path";

import type {
  AppColumnConfig,
  AppTableConfig,
  ResolvedConfig,
} from "../../config/index.ts";
import type { ScaffoldFile } from "./api.ts";

import { FIELD_FORMATS } from "../../config/index.ts";
import { applyCasing } from "../gen/model-types.ts";

export interface ScreensContext {
  readonly config: ResolvedConfig;
  /** The app table, a key of `appTables`. */
  readonly table: string;
  /** `src` or `.`. */
  readonly srcDir: string;
  readonly tsExtensions: boolean;
  /** The route the pages live under, `/<table>` by default. */
  readonly basePath: string;
}

type InputKind =
  | "text"
  | "textarea"
  | "email"
  | "url"
  | "tel"
  | "color"
  | "number"
  | "checkbox"
  | "date"
  | "datetime"
  | "select"
  | "reference";

interface Field {
  readonly column: string;
  readonly prop: string;
  readonly label: string;
  readonly config: AppColumnConfig;
  /** Unset when the form leaves the column to the database. */
  readonly input: InputKind | undefined;
  /** A literal default the form starts from. */
  readonly initial: string | undefined;
  /** The app table a `reference` input lists. */
  readonly target?:
    | { readonly key: string; readonly title: string }
    | undefined;
}

/** Thrown for a table the screens can't serve; the message is for the user. */
export class ScreensError extends Error {}

// The built CLI is scanned for import lines that Node resolves, and next/navigation has no exports map.
const NEXT_NAVIGATION = "next/navigation";

const FUNCTION_DEFAULTS = new Set(["now()", "gen_random_uuid()", "auth.uid()"]);

const quote = (value: string): string => `'${value.replaceAll("'", "\\'")}'`;

const join = (...parts: string[]): string =>
  posix.normalize(posix.join(...parts));

const pascal = (name: string): string =>
  name
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");

function labelOf(column: string): string {
  const words = column.replace(/_id$/, "").split("_");
  const text = words.join(" ");

  return text.charAt(0).toUpperCase() + text.slice(1);
}

function importFrom(context: ScreensContext, from: string, to: string): string {
  let path = posix.relative(posix.dirname(from), to);

  if (!path.startsWith(".")) {
    path = `./${path}`;
  }

  return context.tsExtensions ? path : path.replace(/\.tsx?$/, "");
}

/** The literal a form starts from, or undefined for none or a function default. */
function literalDefault(value: string | undefined): string | undefined {
  if (value === undefined || FUNCTION_DEFAULTS.has(value)) {
    return undefined;
  }

  return value.replace(/^'(.*)'$/, "$1");
}

/** The first text column, which names a row on the list and in pickers. */
function titleColumn(table: AppTableConfig): string {
  const columns = Object.entries(table.columns ?? {});

  return (
    table.subject?.title ??
    columns.find(([, column]) => column.type === "text")?.[0] ??
    "id"
  );
}

function inputOf(
  column: AppColumnConfig,
  config: ResolvedConfig,
): InputKind | undefined {
  if (column.identity === true || FUNCTION_DEFAULTS.has(column.default ?? "")) {
    return undefined;
  }

  if (column.references !== undefined) {
    return "reference";
  }

  switch (column.type) {
    case "text": {
      if (column.options !== undefined) {
        return "select";
      }

      return column.format === undefined
        ? "text"
        : FIELD_FORMATS[column.format].input;
    }

    case "uuid": {
      return "text";
    }

    case "integer":
    case "bigint":
    case "numeric": {
      return "number";
    }

    case "boolean": {
      return "checkbox";
    }

    case "date": {
      return "date";
    }

    case "timestamptz": {
      return config.codecs.timestamptz === "instant" ? undefined : "datetime";
    }

    case "jsonb":
    case "text[]": {
      return undefined;
    }

    default: {
      const unknown: never = column.type;

      throw new Error(`Unknown column type: ${String(unknown)}`);
    }
  }
}

function fieldsOf(context: ScreensContext, table: AppTableConfig): Field[] {
  const { config } = context;

  return Object.entries(table.columns ?? {}).map(([column, settings]) => {
    const input = inputOf(settings, config);
    const reference = settings.references;

    const targetTable =
      reference !== undefined && !("block" in reference)
        ? config.appTables[reference.table]
        : undefined;

    if (
      input === undefined &&
      settings.nullable === false &&
      settings.default === undefined &&
      settings.identity !== true
    ) {
      throw new ScreensError(
        `${context.table}.${column} is required, but the form has no input for a ${settings.type} column. Give it a default or make it nullable.`,
      );
    }

    return {
      column,
      prop: applyCasing(column, config.casing),
      label: labelOf(column),
      config: settings,
      input: input === "reference" && !targetTable ? "text" : input,
      initial: literalDefault(settings.default),
      target:
        targetTable && reference
          ? {
              key: applyCasing(reference.table, config.casing),
              title: applyCasing(titleColumn(targetTable), config.casing),
            }
          : undefined,
    };
  });
}

/** How a form value becomes the column's type, given the generated codecs. */
function parseExpression(field: Field, config: ResolvedConfig): string {
  const name = quote(field.column);

  if (field.input === "checkbox") {
    return `form.get(${name}) === 'on'`;
  }

  const required = field.config.nullable === false;
  const read = required ? `required(form, ${name})` : `optional(form, ${name})`;

  const wrap = (parse: string): string =>
    required ? `${parse}(${read})` : `map(${read}, ${parse})`;

  if (field.config.options !== undefined && field.config.type === "text") {
    const options = `[${field.config.options.map(quote).join(", ")}] as const`;

    return required
      ? `oneOf(${read}, ${options})`
      : `map(${read}, (value) => oneOf(value, ${options}))`;
  }

  const { type } = field.config;

  if (type === "integer") {
    return wrap("Number");
  }

  if (type === "bigint") {
    return INT8_PARSERS[config.codecs.int8](read, wrap);
  }

  if (type === "numeric") {
    return config.codecs.numeric === "string" ? read : wrap("Number");
  }

  return type === "timestamptz" ? wrap("toTimestamp") : read;
}

const INT8_PARSERS: Readonly<
  Record<
    ResolvedConfig["codecs"]["int8"],
    (read: string, wrap: (parse: string) => string) => string
  >
> = {
  bigint: (_read, wrap) => wrap("BigInt"),
  string: (read) => read,
  number: (_read, wrap) => wrap("Number"),
};

interface Names {
  readonly key: string;
  readonly component: string;
  readonly href: string;
  readonly tenant: string | undefined;
  /** The soft-delete column the list and detail pages skip deleted rows by. */
  readonly deletedAt: string | undefined;
  readonly title: string;
  readonly idPattern: string;
  readonly idValue: string;
}

function namesOf(context: ScreensContext, table: AppTableConfig): Names {
  const { config } = context;

  const scope =
    table.scope === undefined || table.scope === "inherit"
      ? (config.sql.scope ?? "tenant")
      : table.scope;

  const bigintId = table.id === "bigint";

  const idValue = bigintId
    ? config.codecs.int8 === "bigint"
      ? "BigInt(id)"
      : config.codecs.int8 === "string"
        ? "id"
        : "Number(id)"
    : "id";

  return {
    key: applyCasing(context.table, config.casing),
    component: pascal(context.table),
    href: context.basePath
      .split("/")
      .filter((segment) => !/^\(.*\)$/.test(segment))
      .join("/"),
    tenant:
      scope === "tenant"
        ? applyCasing(
            `${config.sql.naming?.tenant ?? "organization"}_id`,
            config.casing,
          )
        : undefined,
    deletedAt:
      table.subject?.softDelete === true
        ? applyCasing("deleted_at", config.casing)
        : undefined,
    title: applyCasing(titleColumn(table), config.casing),
    idPattern: bigintId
      ? String.raw`/^\d+$/`
      : String.raw`/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i`,
    idValue,
  };
}

function whereOf(names: Names, extra: string[] = []): string {
  const parts = [
    ...extra,
    ...(names.tenant ? [`${names.tenant}: tenant`] : []),
    ...(names.deletedAt ? [`${names.deletedAt}: { isNull: true }`] : []),
  ];

  return parts.length === 0 ? "" : `, where: { ${parts.join(", ")} }`;
}

function requireCall(names: Names): string {
  return names.tenant
    ? "const { db, tenant } = await bs.require({ requireTenant: true });"
    : "const { db } = await bs.require();";
}

const SHOW = `/** A column value as text for the list and detail pages. */
export function show(value: unknown): string {
  if (value === null || value === undefined) {
    return '';
  }

  if (Array.isArray(value)) {
    return value.map(show).join(', ');
  }

  if (typeof value === 'object' && value.toString === Object.prototype.toString) {
    return JSON.stringify(value);
  }

  return String(value);
}
`;

function listPage(
  context: ScreensContext,
  names: Names,
  fields: readonly Field[],
  paths: Paths,
): string {
  const shown = fields
    .filter((field) => field.config.type !== "jsonb")
    .slice(0, 5);

  const props = [
    ...new Set(["id", names.title, ...shown.map((field) => field.prop)]),
  ];

  const timestamps =
    context.config.appTables[context.table]?.timestamps !== false;

  const order = timestamps
    ? `, orderBy: { ${applyCasing("created_at", context.config.casing)}: 'desc' }`
    : "";

  const cells = props
    .filter((prop) => prop !== "id")
    .map((prop) =>
      prop === names.title
        ? `            <td><Link href={\`${names.href}/\${row.id}\`}>{show(row.${prop}) || row.id}</Link></td>`
        : `            <td>{show(row.${prop})}</td>`,
    );

  const headers = props
    .filter((prop) => prop !== "id")
    .map(
      (prop) =>
        `          <th>${fields.find((field) => field.prop === prop)?.label ?? labelOf(prop)}</th>`,
    );

  return `import Link from 'next/link';
import { Suspense } from 'react';

import { bs } from '${importFrom(context, paths.list, paths.server)}';
import { show } from '${importFrom(context, paths.list, paths.show)}';

export const metadata = { title: '${labelOf(context.table)}' };

/**
 * The ${context.table} list, written once by \`better-supabase scaffold screens\`.
 * The record-grid recipe adds search, filters, saved views and bulk actions.
 */
export default function ${names.component}Page() {
  return (
    <main>
      <h1>${labelOf(context.table)}</h1>
      <p><Link href="${names.href}/new">New</Link></p>
      <Suspense fallback={<p>Loading</p>}>
        <${names.component}List />
      </Suspense>
    </main>
  );
}

async function ${names.component}List() {
  ${requireCall(names)}

  const rows = await db.${names.key}
    .findMany({ select: [${props.map(quote).join(", ")}]${whereOf(names)}${order}, limit: 100 })
    .orThrow();

  if (rows.length === 0) {
    return <p>Nothing here yet. <Link href="${names.href}/new">Add the first one</Link>.</p>;
  }

  return (
    <table>
      <thead>
        <tr>
${headers.join("\n")}
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.id}>
${cells.join("\n")}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
`;
}

function detailPage(
  context: ScreensContext,
  names: Names,
  fields: readonly Field[],
  paths: Paths,
): string {
  const props = ["id", ...fields.map((field) => field.prop)];

  const rows = fields.map(
    (field) =>
      `        <dt>${field.label}</dt>\n        <dd>{show(row.${field.prop})}</dd>`,
  );

  return `import Link from 'next/link';
import { notFound } from '${NEXT_NAVIGATION}';
import { Suspense } from 'react';

import { bs } from '${importFrom(context, paths.detail, paths.server)}';
import { show } from '${importFrom(context, paths.detail, paths.show)}';

export const metadata = { title: '${labelOf(context.table)}' };

/**
 * One row of ${context.table}, written once by \`better-supabase scaffold screens\`.
 * The record-page recipe adds the rows that reference it, comments and tags.
 */
export default function ${names.component}RecordPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  return (
    <main>
      <p><Link href="${names.href}">All ${labelOf(context.table).toLowerCase()}</Link></p>
      <Suspense fallback={<p>Loading</p>}>
        <${names.component}Record params={params} />
      </Suspense>
    </main>
  );
}

async function ${names.component}Record({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  if (!${names.idPattern}.test(id)) {
    notFound();
  }

  ${requireCall(names)}

  const row = await db.${names.key}
    .findFirst({ select: [${props.map(quote).join(", ")}]${whereOf(names, [names.idValue === "id" ? "id" : `id: ${names.idValue}`])} })
    .orThrow();

  if (!row) {
    notFound();
  }

  return (
    <article>
      <h1>{show(row.${names.title}) || row.id}</h1>
      <dl>
${rows.join("\n")}
      </dl>
    </article>
  );
}
`;
}

function newPage(
  context: ScreensContext,
  names: Names,
  fields: readonly Field[],
  paths: Paths,
): string {
  const targets = fields.flatMap((field) =>
    field.input === "reference" && field.target
      ? [{ field, ...field.target }]
      : [],
  );

  const loads = targets.map(
    (target) =>
      `db.${target.key}.findMany({ select: ['id', ${quote(target.title)}], limit: 200 }).orThrow()`,
  );

  const options = targets.map(
    (target, index) =>
      `      ${target.field.column}: ${targets.length === 1 ? "lists" : `lists[${index}]`}.map((row) => ({ value: String(row.id), label: String(row.${target.title} ?? row.id) })),`,
  );

  const header = `export const metadata = { title: 'New ${labelOf(context.table).toLowerCase()}' };

/** The create form for ${context.table}, written once by \`better-supabase scaffold screens\`. */`;

  if (targets.length === 0) {
    return `import { ${names.component}Form } from '${importFrom(context, paths.newPage, paths.form)}';

${header}
export default function New${names.component}Page() {
  return (
    <main>
      <h1>New ${labelOf(context.table).toLowerCase()}</h1>
      <${names.component}Form />
    </main>
  );
}
`;
  }

  return `import { Suspense } from 'react';

import { bs } from '${importFrom(context, paths.newPage, paths.server)}';
import { ${names.component}Form } from '${importFrom(context, paths.newPage, paths.form)}';

${header}
export default function New${names.component}Page() {
  return (
    <main>
      <h1>New ${labelOf(context.table).toLowerCase()}</h1>
      <Suspense fallback={<p>Loading</p>}>
        <${names.component}FormLoader />
      </Suspense>
    </main>
  );
}

/** Loads the rows each reference picker lists. */
async function ${names.component}FormLoader() {
  const { db } = await bs.require(${names.tenant ? "{ requireTenant: true }" : ""});

  const lists = ${targets.length === 1 ? `await ${loads[0]}` : `await Promise.all([\n    ${loads.join(",\n    ")},\n  ])`};

  return (
    <${names.component}Form
      options={{
${options.join("\n")}
      }}
    />
  );
}
`;
}

function inputMarkup(field: Field): string {
  const name = quote(field.column).replaceAll("'", '"');
  const required = field.config.nullable === false ? " required" : "";

  const initial =
    field.initial === undefined
      ? ""
      : ` defaultValue=${JSON.stringify(field.initial)}`;

  const id = `id=${name}`;
  const label = `        <label htmlFor=${name}>${field.label}</label>`;

  switch (field.input) {
    case "checkbox": {
      return `        <label>
          <input type="checkbox" name=${name}${field.initial === "true" ? " defaultChecked" : ""} /> ${field.label}
        </label>`;
    }

    case "select": {
      const choices = (field.config.options ?? [])
        .map(
          (option) =>
            `          <option value=${JSON.stringify(option)}>${option}</option>`,
        )
        .join("\n");

      return `${label}
        <select ${id} name=${name}${required}${initial}>
${field.config.nullable === false ? "" : '          <option value="">None</option>\n'}${choices}
        </select>`;
    }

    case "reference": {
      return `${label}
        <select ${id} name=${name}${required}>
          <option value="">${field.config.nullable === false ? "Pick one" : "None"}</option>
          {options[${name}]?.map((option) => (
            <option key={option.value} value={option.value}>{option.label}</option>
          ))}
        </select>`;
    }

    case "textarea": {
      const max =
        field.config.max === undefined
          ? ""
          : ` maxLength={${field.config.max}}`;

      return `${label}
        <textarea ${id} name=${name}${required}${max}${initial} />`;
    }

    case "number": {
      const min =
        field.config.min === undefined ? "" : ` min={${field.config.min}}`;

      const max =
        field.config.max === undefined ? "" : ` max={${field.config.max}}`;

      const step = field.config.type === "numeric" ? ' step="any"' : "";

      return `${label}
        <input ${id} name=${name} type="number"${min}${max}${step}${required}${initial} />`;
    }

    case "datetime": {
      return `${label}
        <input ${id} name=${name} type="datetime-local"${required} />`;
    }

    case undefined: {
      return "";
    }

    case "text":
    case "email":
    case "url":
    case "tel":
    case "color":
    case "date": {
      const type = field.input === "text" ? "" : ` type="${field.input}"`;

      const max =
        field.config.type === "text" && field.config.max !== undefined
          ? ` maxLength={${field.config.max}}`
          : "";

      return `${label}
        <input ${id} name=${name}${type}${max}${required}${initial} />`;
    }

    default: {
      const unknown: never = field.input;

      throw new Error(`Unknown input: ${String(unknown)}`);
    }
  }
}

function formModule(
  context: ScreensContext,
  names: Names,
  fields: readonly Field[],
  paths: Paths,
): string {
  const inputs = fields
    .filter((field) => field.input !== undefined)
    .map((field) => `      <p>\n${inputMarkup(field)}\n      </p>`);

  const pickers = fields.some((field) => field.input === "reference");

  const props = pickers
    ? `{
  options,
}: {
  options: Readonly<Record<string, readonly Option[]>>;
}`
    : "";

  const option = pickers
    ? `
interface Option {
  readonly value: string;
  readonly label: string;
}
`
    : "";

  return `'use client';

import { useActionState } from 'react';

import { create${names.component} } from '${importFrom(context, paths.form, paths.actions)}';
${option}
/**
 * The create form. Each column gets the input its type, format and options
 * call for; the record-form recipe swaps the selects for searchable pickers.
 */
export function ${names.component}Form(${props}) {
  const [state, action, pending] = useActionState(create${names.component}, { error: null });

  return (
    <form action={action}>
${inputs.join("\n")}
      {state.error ? <p role="alert">{state.error}</p> : null}
      <button type="submit" disabled={pending}>Create</button>
    </form>
  );
}
`;
}

function actionsModule(
  context: ScreensContext,
  names: Names,
  fields: readonly Field[],
  paths: Paths,
): string {
  const values = fields
    .filter((field) => field.input !== undefined)
    .map(
      (field) =>
        `    ${field.prop}: ${parseExpression(field, context.config)},`,
    );

  const tenant = names.tenant ? `, ${names.tenant}: tenant` : "";
  const code = values.join("\n");

  const helpers = HELPERS.filter(([name]) => code.includes(`${name}(`))
    .map(([, source]) => `${source}\n`)
    .join("");

  return `'use server';

import { redirect } from '${NEXT_NAVIGATION}';

import { bs } from '${importFrom(context, paths.actions, paths.server)}';

export interface CreateState {
  readonly error: string | null;
}

/** A form value the action refuses; the message is shown on the form. */
class FieldError extends Error {}

${helpers}function valuesOf(form: FormData) {
  return {
${values.join("\n")}
  };
}

/** Creates a row from the form, then opens it. The table's policies check the caller. */
export async function create${names.component}(
  _state: CreateState,
  form: FormData,
): Promise<CreateState> {
  ${requireCall(names)}

  let values: ReturnType<typeof valuesOf>;

  try {
    values = valuesOf(form);
  } catch (error) {
    if (error instanceof FieldError) {
      return { error: error.message };
    }

    throw error;
  }

  const created = await db.${names.key}.create({ ...values${tenant} }, { select: ['id'] });

  if (!created.ok) {
    return { error: created.error.message };
  }

  redirect(\`${names.href}/\${created.data.id}\`);
}
`;
}

const HELPERS: readonly (readonly [string, string])[] = [
  [
    "optional",
    `function optional(form: FormData, name: string): string | null {
  const value = form.get(name);

  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}
`,
  ],
  [
    "required",
    `function required(form: FormData, name: string): string {
  const value = form.get(name);

  if (typeof value !== 'string' || value.trim() === '') {
    throw new FieldError(\`Fill in \${name}.\`);
  }

  return value.trim();
}
`,
  ],
  [
    "map",
    `function map<T>(value: string | null, parse: (value: string) => T): T | null {
  return value === null ? null : parse(value);
}
`,
  ],
  [
    "oneOf",
    `function oneOf<const T extends string>(value: string, options: readonly T[]): T {
  const found = options.find((option) => option === value);

  if (found === undefined) {
    throw new FieldError(\`\${value} is not one of the options.\`);
  }

  return found;
}
`,
  ],
  [
    "toTimestamp",
    `function toTimestamp(value: string): string {
  return new Date(value).toISOString();
}
`,
  ],
];

interface Paths {
  readonly server: string;
  readonly show: string;
  readonly list: string;
  readonly newPage: string;
  readonly detail: string;
  readonly form: string;
  readonly actions: string;
}

/** The pages `scaffold screens <table>` writes for Next.js, each written once. */
export function scaffoldScreensFiles(context: ScreensContext): ScaffoldFile[] {
  const table = context.config.appTables[context.table];

  if (!table) {
    const known = Object.keys(context.config.appTables);

    throw new ScreensError(
      known.length === 0
        ? `"${context.table}" is not an app table, and the config has none. Add it under appTables first.`
        : `"${context.table}" is not an app table. App tables: ${known.join(", ")}.`,
    );
  }

  if (table.scope === "none") {
    throw new ScreensError(
      `${context.table} has scope "none", so only the service role writes it. Screens need a table the caller writes.`,
    );
  }

  if (/[[\]]/.test(context.basePath)) {
    throw new ScreensError(
      `--base-path takes a static route, got "${context.basePath}". Move the pages under a dynamic segment yourself.`,
    );
  }

  const fields = fieldsOf(context, table);
  const names = namesOf(context, table);
  const dir = join(context.srcDir, "app", context.basePath);

  const ext = (name: string, tsx: boolean): string =>
    join(dir, `${name}.${tsx ? "tsx" : "ts"}`);

  const paths: Paths = {
    server: join(context.srcDir, "lib", "supabase", "server.ts"),
    show: ext("show", false),
    list: ext("page", true),
    newPage: join(dir, "new", "page.tsx"),
    detail: join(dir, "[id]", "page.tsx"),
    form: ext("form", true),
    actions: ext("actions", false),
  };

  return [
    {
      path: paths.list,
      generated: false,
      contents: listPage(context, names, fields, paths),
    },
    {
      path: paths.newPage,
      generated: false,
      contents: newPage(context, names, fields, paths),
    },
    {
      path: paths.detail,
      generated: false,
      contents: detailPage(context, names, fields, paths),
    },
    {
      path: paths.form,
      generated: false,
      contents: formModule(context, names, fields, paths),
    },
    {
      path: paths.actions,
      generated: false,
      contents: actionsModule(context, names, fields, paths),
    },
    { path: paths.show, generated: false, contents: SHOW },
  ];
}
