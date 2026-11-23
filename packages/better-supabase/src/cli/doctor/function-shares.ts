import type { CatalogFunction, CatalogTable } from "../../config/snapshot.ts";
import type { DoctorContext, FindingInput } from "./rules.ts";

import { providerLabel } from "../authorization.ts";
import { strings } from "../schema-reader/ast.ts";
import { parseStatements } from "../schema-reader/index.ts";
import { walk } from "../schema-reader/walk.ts";
import { catalogOf, qualified } from "./shared.ts";

/** Functions that read who the caller is, so two holders can get different rows. */
const IDENTITY = new Set([
  "current_setting",
  "current_user_id",
  "session_user",
  "current_user",
]);

/**
 * The keywords among `current_date`, `current_user` and the like that name a
 * role.
 */
const CALLER_VALUES = new Set([
  "SVFOP_CURRENT_ROLE",
  "SVFOP_CURRENT_USER",
  "SVFOP_USER",
  "SVFOP_SESSION_USER",
]);

/** What a function body reads, from its parse tree. */
interface BodyReads {
  readonly relations: readonly { schema?: string; name: string }[];
  readonly calls: readonly string[];
  /** `current_user`, `session_user` and the like. */
  readonly identity: boolean;
}

async function readsOf(source: string): Promise<BodyReads | undefined> {
  let statements;

  try {
    statements = await parseStatements(source);
  } catch {
    return undefined;
  }

  const relations: { schema?: string; name: string }[] = [];
  const calls: string[] = [];
  const ctes = new Set<string>();
  let identity = false;

  walk(
    statements.map((statement) => statement.stmt),
    {
      CommonTableExpr: (node) => {
        if (node.ctename) {
          ctes.add(node.ctename);
        }
      },
      RangeVar: (node) => {
        if (node.relname) {
          relations.push({
            ...(node.schemaname ? { schema: node.schemaname } : {}),
            name: node.relname,
          });
        }
      },
      FuncCall: (node) => {
        calls.push(strings(node.funcname).join("."));
      },
      SQLValueFunction: (node) => {
        identity ||= CALLER_VALUES.has(String(node.op));
      },
    },
  );

  return {
    relations: relations.filter(
      (relation) => relation.schema !== undefined || !ctes.has(relation.name),
    ),
    calls,
    identity,
  };
}

/** The declared table `name` (an app key or `schema.name`) in the catalog. */
function tableNamed(
  tables: readonly CatalogTable[],
  name: string,
): CatalogTable | undefined {
  return tables.find(
    (table) => table.name === name || qualified(table) === name,
  );
}

/** Why a shared function can't be shared, or `undefined` when it can. */
async function problemOf(
  fn: CatalogFunction,
  source: string | undefined,
  declared: ReadonlySet<string>,
  shared: ReadonlySet<string>,
  readSchemas: readonly string[],
  functions: readonly CatalogFunction[],
): Promise<string | undefined> {
  if (fn.securityDefiner) {
    return "it is security definer, so it reads past the caller's RLS. Make it security invoker";
  }

  if (fn.language !== "sql") {
    return `it is written in ${fn.language}, whose body doctor can't read. Rewrite it in language sql, or read its tables from the entry instead`;
  }

  if (fn.volatility === "volatile") {
    return "it is volatile, so it may write or return different rows per call. Mark it stable";
  }

  if (source === undefined || source.trim() === "") {
    return "the catalog has no body for it";
  }

  const reads = await readsOf(source);

  if (!reads) {
    return "its body doesn't parse";
  }

  if (reads.identity) {
    return "it reads the caller (current_user or session_user)";
  }

  for (const call of reads.calls) {
    const [first, second] = call.split(".");
    const name = second ?? first ?? call;
    const schema = second === undefined ? undefined : first;

    if (schema === "auth" || IDENTITY.has(name)) {
      return `it calls ${call}, which reads the caller`;
    }

    const target = functions.find(
      (candidate) =>
        candidate.name === name &&
        (schema === undefined
          ? readSchemas.includes(candidate.schema)
          : candidate.schema === schema),
    );

    if (target && !shared.has(target.name)) {
      return `it calls ${qualifiedFn(target)}, which sharedFunctions doesn't list`;
    }
  }

  // An unqualified name resolves through the function's search_path.
  const path =
    fn.searchPath === null
      ? [fn.schema, "public"]
      : fn.searchPath
          .split(",")
          .map((part) => part.trim().replaceAll('"', ""))
          .filter((part) => part !== "" && part !== "$user");

  for (const relation of reads.relations) {
    const names =
      relation.schema === undefined
        ? path.map((schema) => `${schema}.${relation.name}`)
        : [`${relation.schema}.${relation.name}`];

    if (!names.some((name) => declared.has(name))) {
      return `it reads ${names[0] ?? relation.name}, which its tables don't list`;
    }
  }

  return undefined;
}

const qualifiedFn = (fn: CatalogFunction): string => `${fn.schema}.${fn.name}`;

/**
 * The provider's `sharedFunctions` a shared fill can't trust: a function that
 * isn't security invoker, isn't `language sql`, is volatile, reads the caller,
 * or reads a table or calls a function its entry doesn't list.
 */
export async function functionShares(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const provider = context.config.authorization;
  const declared = Object.entries(provider?.sharedFunctions ?? {});

  if (!provider || declared.length === 0) {
    return [];
  }

  const catalog = catalogOf(context);

  const shared = new Set(
    declared.map(([name]) => name.split(".").at(-1) ?? name),
  );

  const findings: FindingInput[] = [];

  for (const [key, entry] of declared) {
    const target = `authorization.sharedFunctions.${key}`;

    const [schema, name] = key.includes(".")
      ? key.split(".", 2)
      : ["public", key];

    const fn = catalog.functions.find(
      (candidate) => candidate.schema === schema && candidate.name === name,
    );

    if (!fn) {
      findings.push({
        message: `${providerLabel(provider)} declares ${key} in sharedFunctions, but the database has no such function.`,
        target,
      });
      continue;
    }

    const tables = new Set<string>();

    for (const table of entry.tables) {
      const found = tableNamed(catalog.tables, table);

      if (found) {
        tables.add(qualified(found));
      } else {
        findings.push({
          message: `${providerLabel(provider)} declares ${qualifiedFn(fn)} as reading ${table}, but the database has no such table.`,
          target,
        });
      }

      if (provider.tables?.[table]?.share !== "tenant") {
        findings.push({
          message: `${providerLabel(provider)} declares ${qualifiedFn(fn)} as reading ${table}, which its tables don't share per tenant, so no shared fill can call the function.`,
          target,
        });
      }
    }

    const problem = await problemOf(
      fn,
      fn.source ?? context.snapshot.extras.functionSources?.[qualifiedFn(fn)],
      tables,
      shared,
      context.config.schemas,
      catalog.functions,
    );

    if (problem) {
      findings.push({
        message: `${providerLabel(provider)} declares ${qualifiedFn(fn)} in sharedFunctions, but ${problem}. A shared entry could hand one caller's rows to another.`,
        target,
        object: { kind: "function", schema: fn.schema, name: fn.name },
      });
    }
  }

  return findings;
}
