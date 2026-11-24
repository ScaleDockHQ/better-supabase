import type {
  AuthorizationPermissionFilter,
  AuthorizationProvider,
} from "../../config/index.ts";
import type { CatalogFunction, CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput } from "./rules.ts";

import { providerLabel } from "../authorization.ts";
import { bodyOf, list, obj, str, strings } from "../schema-reader/ast.ts";
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

/** The library's schema: a helper there that passes needs no listing. */
const LIBRARY_SCHEMA = "better_supabase";

/** One function call in a body: its name parts and its arguments. */
interface BodyCall {
  readonly name: readonly string[];
  readonly args: readonly unknown[];
}

/** What a function body reads, from its parse tree. */
interface BodyReads {
  readonly relations: readonly { schema?: string; name: string }[];
  readonly calls: readonly BodyCall[];
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
  const calls: BodyCall[] = [];
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
        calls.push({ name: strings(node.funcname), args: list(node.args) });
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

/** The string a literal argument holds, through any `::type` cast. */
function literal(node: unknown): string | undefined {
  const cast = bodyOf(node, "TypeCast");

  if (cast !== undefined) {
    return literal(cast["arg"]);
  }

  return str(obj(bodyOf(node, "A_Const")?.["sval"])["sval"]);
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

const qualifiedFn = (fn: CatalogFunction): string => `${fn.schema}.${fn.name}`;

/** `name` or `schema.name`, as `schema.name` with `public` by default. */
export const qualifiedName = (name: string): string =>
  name.includes(".") ? name : `public.${name}`;

/** The schemas an unqualified name in `fn`'s body resolves through. */
function searchPathOf(fn: CatalogFunction): readonly string[] {
  return fn.searchPath === null
    ? [fn.schema, "public"]
    : fn.searchPath
        .split(",")
        .map((part) => part.trim().replaceAll('"', ""))
        .filter((part) => part !== "" && part !== "$user");
}

/** The result of checking one function, with the functions it calls. */
export interface ShareCheck {
  /** `schema.name`. */
  readonly name: string;
  /** Why a shared fill can't call it; empty when it can. */
  readonly reasons: readonly string[];
  /** The tables it and the functions it calls read, as `schema.name`. */
  readonly reads: readonly string[];
  /** The tables among those reads that the entry or the provider doesn't allow. */
  readonly outside: readonly string[];
  /** The literal keys it passes to the provider's `permissionFilters`. */
  readonly permissions: readonly string[];
  /** Whether `sharedFunctions` lists it. */
  readonly listed: boolean;
  /** The functions it calls in the read schemas, checked the same way. */
  readonly calls: readonly ShareCheck[];
}

/** What `checkShareable` checks a function against. */
export interface ShareScope {
  readonly functions: readonly CatalogFunction[];
  readonly sources: Readonly<Record<string, string>> | undefined;
  /** `schema.name` of every `sharedFunctions` entry. */
  readonly listed: ReadonlySet<string>;
  /** The provider's `permissionFilters`, by `schema.name`. */
  readonly filters: Readonly<Record<string, AuthorizationPermissionFilter>>;
  /**
   * The entry's tables as `schema.name`. Without it, as for a candidate that
   * `sharedFunctions` doesn't list yet, a read must be a table the provider
   * shares per tenant.
   */
  readonly tables?: ReadonlySet<string>;
  /** `schema.name` of the tables the provider shares per tenant. */
  readonly tenantTables: ReadonlySet<string>;
}

/** `scope` for a provider over a catalog. */
export function shareScope(
  provider: AuthorizationProvider,
  functions: readonly CatalogFunction[],
  tables: readonly CatalogTable[],
  sources: Readonly<Record<string, string>> | undefined,
): ShareScope {
  const tenantTables = new Set(
    Object.entries(provider.tables ?? {}).flatMap(([name, entry]) => {
      const found = tableNamed(tables, name);

      return entry.share === "tenant" && found ? [qualified(found)] : [];
    }),
  );

  return {
    functions,
    sources,
    listed: new Set(
      Object.keys(provider.sharedFunctions ?? {}).map(qualifiedName),
    ),
    filters: Object.fromEntries(
      Object.entries(provider.permissionFilters ?? {}).map(([name, filter]) => [
        qualifiedName(name),
        filter,
      ]),
    ),
    tenantTables,
  };
}

const PASSED: Omit<ShareCheck, "name" | "listed"> = {
  reasons: [],
  reads: [],
  outside: [],
  permissions: [],
  calls: [],
};

/**
 * Every reason a shared fill can't call `fn`, and the same check for each
 * function it calls. A function that calls itself is checked once.
 */
export async function checkShareable(
  fn: CatalogFunction,
  scope: ShareScope,
  seen: Set<string> = new Set<string>(),
): Promise<ShareCheck> {
  const name = qualifiedFn(fn);
  const listed = scope.listed.has(name);

  if (seen.has(name)) {
    return { name, listed, ...PASSED };
  }

  seen.add(name);

  const reasons: string[] = [];
  const reads = new Set<string>();
  const outside = new Set<string>();
  const permissions = new Set<string>();
  const calls: ShareCheck[] = [];

  if (fn.securityDefiner) {
    reasons.push(
      "it is security definer, so it reads past the caller's RLS. Make it security invoker",
    );
  }

  if (fn.language !== "sql") {
    reasons.push(
      `it is written in ${fn.language}, whose body doctor can't read. Rewrite it in language sql`,
    );
  }

  if (fn.volatility === "volatile") {
    reasons.push(
      "it is volatile, so it may write or return different rows per call. Mark it stable",
    );
  }

  const source = fn.source ?? scope.sources?.[name];
  let body: BodyReads | undefined;

  if (fn.language === "sql") {
    if (source === undefined || source.trim() === "") {
      reasons.push("the catalog has no body for it");
    } else {
      body = await readsOf(source);

      if (!body) {
        reasons.push("its body doesn't parse");
      }
    }
  }

  if (body) {
    if (body.identity) {
      reasons.push("it reads the caller (current_user or session_user)");
    }

    const path = searchPathOf(fn);

    for (const call of body.calls) {
      const callee = call.name.at(-1) ?? "";
      const schema = call.name.length > 1 ? call.name.at(-2) : undefined;
      const text = call.name.join(".");

      if (schema === "auth" || IDENTITY.has(callee)) {
        reasons.push(
          callee === "current_setting"
            ? `it calls ${text}, which reads the caller's settings and claims`
            : `it calls ${text}, which reads the caller`,
        );
        continue;
      }

      const candidates =
        schema === undefined
          ? path.map((entry) => `${entry}.${callee}`)
          : [`${schema}.${callee}`];

      const filterName = candidates.find((entry) => entry in scope.filters);

      if (filterName !== undefined) {
        const filter = scope.filters[filterName]!;
        const key = literal(call.args[filter.keyArgument]);

        if (key === undefined) {
          reasons.push(
            `it calls ${filterName} with a permission key that isn't a string literal, so the key can't join the share key`,
          );
        } else {
          permissions.add(key);
        }

        continue;
      }

      const target = candidates
        .map((entry) =>
          scope.functions.find((candidate) => qualifiedFn(candidate) === entry),
        )
        .find((found) => found !== undefined);

      if (!target) {
        if (schema !== undefined && schema !== "pg_catalog") {
          reasons.push(
            `it calls ${text}, which isn't in the schemas doctor read, so doctor can't check it`,
          );
        }

        continue;
      }

      const checked = await checkShareable(target, scope, seen);

      calls.push(checked);

      for (const table of checked.reads) {
        reads.add(table);
      }

      for (const key of checked.permissions) {
        permissions.add(key);
      }

      for (const table of checked.outside) {
        outside.add(table);
      }

      if (checked.listed) {
        for (const table of checked.outside) {
          reasons.push(
            `it calls ${checked.name}, which reads ${table}, outside the tables of this entry`,
          );
        }

        continue;
      }

      if (target.schema === LIBRARY_SCHEMA) {
        if (checked.reasons.length > 0) {
          reasons.push(
            `it calls ${checked.name}, which a shared function can't call: ${checked.reasons.join("; ")}`,
          );
        }

        continue;
      }

      reasons.push(
        checked.reasons.length === 0
          ? `it calls ${checked.name}, which sharedFunctions doesn't list (it passes on its own, so listing it is enough)`
          : `it calls ${checked.name}, which sharedFunctions doesn't list and which can't be shared either: ${checked.reasons.join("; ")}`,
      );
    }

    for (const relation of body.relations) {
      const names =
        relation.schema === undefined
          ? path.map((entry) => `${entry}.${relation.name}`)
          : [`${relation.schema}.${relation.name}`];

      const allowed = scope.tables ?? scope.tenantTables;
      const found = names.find((entry) => allowed.has(entry));

      if (found) {
        reads.add(found);
      } else {
        outside.add(names[0] ?? relation.name);
        reasons.push(
          scope.tables
            ? `it reads ${names[0] ?? relation.name}, which its tables don't list`
            : `it reads ${names[0] ?? relation.name}, which the provider's tables don't share per tenant`,
        );
      }
    }
  }

  return {
    name,
    reasons,
    reads: [...reads].toSorted(),
    outside: [...outside].toSorted(),
    permissions: [...permissions].toSorted(),
    listed,
    calls,
  };
}

/**
 * The provider's `sharedFunctions` a shared fill can't trust, with every reason
 * per function: a function that is security definer, isn't `language sql`, is
 * volatile, reads the caller, reads a table its entry doesn't list, or calls a
 * function that doesn't pass the same check.
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

  const base = shareScope(
    provider,
    catalog.functions,
    catalog.tables,
    context.snapshot.extras.functionSources,
  );

  const findings: FindingInput[] = [];

  for (const [key, entry] of declared) {
    const target = `authorization.sharedFunctions.${key}`;
    const name = qualifiedName(key);

    const fn = catalog.functions.find(
      (candidate) => qualifiedFn(candidate) === name,
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

    const checked = await checkShareable(fn, { ...base, tables });

    const declaredKeys = new Set<string>(entry.permissions);

    const reasons = [
      ...checked.reasons,
      ...checked.permissions
        .filter((permission) => !declaredKeys.has(permission))
        .map(
          (permission) =>
            `it filters by the permission ${permission}, which its permissions don't list, so the share key leaves it out. Add it`,
        ),
    ];

    if (reasons.length > 0) {
      findings.push({
        message: `${providerLabel(provider)} declares ${qualifiedFn(fn)} in sharedFunctions, but ${reasons.length === 1 ? reasons[0] : reasons.map((reason, index) => `(${String(index + 1)}) ${reason}`).join("; ")}. A shared entry could hand one caller's rows to another.`,
        target,
        object: { kind: "function", schema: fn.schema, name: fn.name },
      });
    }
  }

  return findings;
}
