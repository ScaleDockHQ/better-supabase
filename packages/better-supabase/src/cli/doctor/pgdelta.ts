import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { diffEngine } from "../supabase-toml.ts";

/** Comments blanked out, so a commented-out statement never matches and line numbers stay. */
function withoutComments(text: string): string {
  return text
    .replaceAll(/\/\*[\s\S]*?\*\//g, (comment) =>
      comment.replaceAll(/[^\n]/g, " "),
    )
    .replaceAll(/--[^\n]*/g, (comment) => " ".repeat(comment.length));
}

const lineAt = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

/**
 * The declarative schema files pg-delta loads, outside the SQL module files
 * better-supabase writes, when the project diffs with pg-delta.
 */
function pgdeltaSchemaFiles(context: DoctorContext): readonly TextFile[] {
  const toml = context.configToml;
  if (toml === undefined || diffEngine(toml) !== "pg-delta") return [];
  const schemas = `${toml.dir}/schemas/`;
  return (context.sqlFiles ?? []).filter(
    (file) =>
      file.path.startsWith(schemas) && !/^-- @bs-module /m.test(file.text),
  );
}

const BULK_GRANT =
  /\bgrant\b[^;]*?\bon\s+all\s+(tables|routines|functions|procedures|sequences)\s+in\s+schema\s+("?[\w$]+"?(?:\s*,\s*"?[\w$]+"?)*)\s+to\s+([^;]*)/gi;

/** Grantees a bulk grant must not reach: the Data API roles and `public`. */
const API_ROLES = /\b(anon|authenticated|public)\b/i;

/** `do` blocks; group 2 is the body. */
const DO_BLOCK = /\bdo\s+(\$[\w]*\$)([\s\S]*?)\1/gi;

const CATALOG =
  /\b(information_schema\.\w+|(?:pg_catalog\.)?pg_(?:class|tables|views|proc|namespace|attribute|trigger|constraint|index|type|policies|matviews))\b/i;

const EXECUTES = /\b(execute|perform)\b/i;

function bulkGrants(context: DoctorContext): FindingInput[] {
  return pgdeltaSchemaFiles(context).flatMap((file) => {
    const text = withoutComments(file.text);
    return [...text.matchAll(BULK_GRANT)]
      .filter((match) => API_ROLES.test(match[3]!))
      .map((match) => ({
        message: `${file.path} grants on all ${match[1]!.toLowerCase()} in schema ${match[2]} at once. pg-delta gives a bulk grant no dependency position, so it can run after the per-object revokes and open functions and tables to anon and authenticated again. Grant each object by name next to its definition, or set Supabase default privileges (alter default privileges in schema ... grant ...) for objects created later.`,
        target: file.path,
        location: { file: file.path, line: lineAt(text, match.index) },
      }));
  });
}

function catalogLoops(context: DoctorContext): FindingInput[] {
  return pgdeltaSchemaFiles(context).flatMap((file) => {
    const text = withoutComments(file.text);
    return [...text.matchAll(DO_BLOCK)].flatMap((match) => {
      const body = match[2]!;
      const catalog = CATALOG.exec(body);
      if (!catalog || !EXECUTES.test(body)) return [];
      return [
        {
          message: `${file.path} has a do block that reads ${catalog[1]} to create objects. pg-delta runs a do block with no dependency position, before the tables it looks for exist, so it creates nothing and the diff never sees its objects. Write the statements it would generate (one trigger, grant or policy per table) as static SQL, or call a per-table function such as better_supabase.audit('<table>') or track_updated_at('<table>') once per table.`,
          target: file.path,
          location: { file: file.path, line: lineAt(text, match.index) },
        },
      ];
    });
  });
}

const CREATE_EXTENSION =
  /\bcreate\s+extension\s+(?:if\s+not\s+exists\s+)?"?([\w-]+)"?/gi;

/**
 * Extensions a pg-delta schema file creates, SQL module files included, that
 * no migration creates. pg-delta can leave an extension that owns its own
 * schema (`pgmq`) out of the generated migration.
 */
function missingExtensions(context: DoctorContext): FindingInput[] {
  const toml = context.configToml;
  if (toml === undefined || diffEngine(toml) !== "pg-delta") return [];
  const files = context.sqlFiles ?? [];
  const migrations = files.filter((file) =>
    file.path.startsWith(`${toml.dir}/migrations/`),
  );
  if (migrations.length === 0) return [];
  const created = new Set(
    migrations.flatMap((file) =>
      [...withoutComments(file.text).matchAll(CREATE_EXTENSION)].map((match) =>
        match[1]!.toLowerCase(),
      ),
    ),
  );
  const seen = new Set<string>();
  return files
    .filter((file) => file.path.startsWith(`${toml.dir}/schemas/`))
    .flatMap((file) => {
      const text = withoutComments(file.text);
      return [...text.matchAll(CREATE_EXTENSION)].flatMap((match) => {
        const name = match[1]!.toLowerCase();
        if (created.has(name) || seen.has(name)) return [];
        seen.add(name);
        const module = /^-- @bs-module /m.test(file.text);
        return [
          {
            message: `${file.path} creates the extension ${name}, but no migration creates it. pg-delta can leave an extension that owns its own schema out of the generated migration, and a database built from the migrations then lacks it. ${module ? "Run `better-supabase sql data`: the module's data file creates it." : `Add \`create extension if not exists ${name};\` to a migration.`}`,
            target: file.path,
            location: { file: file.path, line: lineAt(text, match.index) },
          },
        ];
      });
    });
}

/** Statements in declarative schema files that pg-delta can't order. */
export const PGDELTA_RULES: readonly Rule[] = [
  {
    code: "BS317",
    severity: "warning",
    title: "Bulk grant in a pg-delta schema file",
    description:
      "A `grant ... on all tables|routines|sequences in schema ... to anon|authenticated|public` statement in `supabase/schemas` under pg-delta. pg-delta can't place it after the objects it covers or before the revokes that narrow them, so it can re-open functions and tables to `anon` and `authenticated`.",
    check: bulkGrants,
  },
  {
    code: "BS318",
    severity: "warning",
    title: "Catalog loop in a pg-delta schema file",
    description:
      "A `do` block in `supabase/schemas` under pg-delta that reads the catalog (`information_schema`, `pg_class`, ...) to create objects. pg-delta runs it before the tables exist, so it creates nothing.",
    check: catalogLoops,
  },
  {
    code: "BS321",
    severity: "warning",
    title: "Extension missing from the migrations under pg-delta",
    description:
      "A `create extension` in `supabase/schemas` (a SQL module's file included) under pg-delta that no migration repeats. pg-delta can leave an extension that owns its own schema, such as `pgmq`, out of the generated migration.",
    check: missingExtensions,
  },
];
