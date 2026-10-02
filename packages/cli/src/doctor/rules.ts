import type { ResolvedConfig } from "better-supabase/config";

import {
  type KitLayout,
  kitLayout,
  renderKit,
  sameKitFile,
} from "better-supabase/sql";
import { defineBucket, parseSize } from "better-supabase/storage";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { CatalogPolicy, Snapshot } from "../introspect/types.ts";
import type { PermdockProject } from "../permdock.ts";
import type { SupabaseToml, TomlValue } from "../supabase-toml.ts";
import type { AdvisorCategory, AdvisorSource, Lint } from "./advisors.ts";
import type { ExplainRequest, LiveDatabase } from "./live.ts";

import { renderFiles } from "../commands/gen.ts";
import { tomlGet } from "../supabase-toml.ts";
import { HOOK_RULES } from "./hooks.ts";
import { LIVE_RULES } from "./live.ts";
import { entitlementsKit, PERMDOCK_RULES } from "./permdock.ts";
import { permissiveOverlaps, RLS_RULES } from "./rls.ts";
import {
  catalogOf,
  exposed,
  lineOf,
  policyObject,
  qualified,
  tableObject,
} from "./shared.ts";

export { lineOf };

export type Severity = "error" | "warning" | "info";

export interface Location {
  /** Path relative to the project root. */
  readonly file: string;
  readonly line: number;
}

/** A database object a finding is about, used to find where it is declared. */
export interface SqlObject {
  readonly kind: "table" | "function" | "policy";
  readonly schema: string;
  readonly name: string;
}

export interface Finding {
  readonly code: string;
  readonly severity: Severity;
  readonly title: string;
  readonly message: string;
  /** `public.customers`, `public.customers.organization_id`, `.env.local:SUPABASE_SECRET_KEY`. */
  readonly target?: string;
  readonly location?: Location;
  readonly object?: SqlObject;
  readonly help: string;
}

/** Rules fill in code, severity, title and help; advisor findings override them. */
export type FindingInput = Omit<
  Finding,
  "code" | "severity" | "title" | "help"
> &
  Partial<Pick<Finding, "severity" | "title" | "help">>;

export interface TextFile {
  /** Relative to the project root. */
  readonly path: string;
  readonly text: string;
}

export interface DoctorContext {
  readonly config: ResolvedConfig;
  readonly snapshot: Snapshot;
  readonly configToml: SupabaseToml | undefined;
  readonly envFiles: readonly TextFile[];
  readonly gitignore: string;
  /** App source files matched by `doctor.sources`. */
  readonly sources: readonly TextFile[];
  /** `config.readSets`, compiled, or why they could not be loaded. */
  readonly readSets?: KitLayout["readSets"] | { readonly skipped: string };
  /**
   * Supabase advisors for the database being checked, or why they were
   * skipped (a saved snapshot has no database to lint).
   */
  readonly advisors?: AdvisorSource | { readonly skipped: string };
  /** The database being checked, for statistics and plans (BS208, BS209, BS212). */
  readonly database?: LiveDatabase | { readonly skipped: string };
  /** `--stats`: read `pg_stat_statements` (BS209). */
  readonly stats?: boolean;
  /** `--explain`: tables to plan and the claims to plan them as (BS212). */
  readonly explain?: ExplainRequest;
  /** `--as`: the user to call the custom access token hook for (BS405). */
  readonly hookUser?: string;
  /** The PermDock config, manifest and catalog in the project root, if any (BS213, BS214, BS405, BS407). */
  readonly permdock?: PermdockProject;
  /** `supabase/schemas` in `schema_paths` order, then migrations newest first (BS214, BS404, BS407). */
  readonly sqlFiles?: readonly TextFile[];
  /** Codes of the rules in this run, so a rule can defer to another. */
  readonly codes?: readonly string[];
}

export interface Rule {
  readonly code: string;
  readonly severity: Severity;
  readonly title: string;
  readonly description: string;
  readonly check: (
    context: DoctorContext,
  ) => FindingInput[] | Promise<FindingInput[]>;
}

export const DOCS_URL = "https://bettersupabase.com/docs/cli/doctor";

const writes = (policy: CatalogPolicy): boolean =>
  policy.command === "all" ||
  policy.command === "insert" ||
  policy.command === "update" ||
  policy.command === "delete";

const publicRoles = (policy: CatalogPolicy): boolean =>
  policy.roles.length === 0 ||
  policy.roles.some((role) => role === "public" || role === "anon");

const isTrue = (expression: string | null): boolean =>
  expression !== null && /^\(*\s*true\s*\)*$/i.test(expression.trim());

function authSetting(
  context: DoctorContext,
  key: string,
): TomlValue | undefined {
  return context.configToml
    ? tomlGet(context.configToml.document, ["auth", key])
    : undefined;
}

function tomlLocation(
  context: DoctorContext,
  key: string,
): Location | undefined {
  if (!context.configToml) return undefined;
  const line =
    lineOf(context.configToml.text, new RegExp(`^\\s*${key}\\s*=`)) ??
    lineOf(context.configToml.text, /^\[auth\]/);
  return line ? { file: context.configToml.path, line } : undefined;
}

const PUBLIC_PREFIXES = [
  "NEXT_PUBLIC_",
  "VITE_",
  "PUBLIC_",
  "EXPO_PUBLIC_",
  "NUXT_PUBLIC_",
];

function envEntries(
  file: TextFile,
): { key: string; value: string; line: number }[] {
  return file.text.split("\n").flatMap((raw, index) => {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(
      raw,
    );
    if (!match) return [];
    const value = match[2]!.trim().replace(/^(['"])(.*)\1$/, "$2");
    return [{ key: match[1]!, value, line: index + 1 }];
  });
}

const ADVISOR_SEVERITY: Record<Lint["level"], Severity> = {
  ERROR: "error",
  WARN: "warning",
  INFO: "info",
};

function lintObject(lint: Lint): SqlObject | undefined {
  const { schema, name, type } = lint.metadata ?? {};
  if (typeof schema !== "string" || typeof name !== "string") return undefined;
  if (type === "table" || type === "view")
    return { kind: "table", schema, name };
  if (type === "function") return { kind: "function", schema, name };
  return undefined;
}

function lintFinding(lint: Lint): FindingInput {
  const object = lintObject(lint);
  return {
    // oxlint-disable-next-line typescript/no-unnecessary-condition -- splinter can add levels this map does not know.
    severity: ADVISOR_SEVERITY[lint.level] ?? "warning",
    title: lint.title,
    message: `${lint.detail.replaceAll("\\`", "`")} [${lint.name}]`,
    target: object ? `${object.schema}.${object.name}` : lint.cache_key,
    help: lint.remediation,
    ...(object ? { object } : {}),
  };
}

function advisorRule(
  code: string,
  category: AdvisorCategory,
  title: string,
  description: string,
  covered: (lint: Lint, context: DoctorContext) => boolean = () => false,
): Rule {
  return {
    code,
    severity: "warning",
    title,
    description,
    async check(context) {
      const { advisors } = context;
      if (!advisors) return [];
      if ("skipped" in advisors) {
        return [
          {
            severity: "info",
            message: `Skipped the ${category} advisor: ${advisors.skipped}`,
          },
        ];
      }
      try {
        return (await advisors.lints(category))
          .filter((lint) => !covered(lint, context))
          .map(lintFinding);
      } catch (cause) {
        return [
          {
            message: `The ${category} advisor could not run (${advisors.describe}): ${cause instanceof Error ? cause.message : String(cause)}`,
          },
        ];
      }
    },
  };
}

/** splinter's `multiple_permissive_policies` for a table BS207 reports. */
function coveredByBS207(lint: Lint, context: DoctorContext): boolean {
  if (lint.name !== "multiple_permissive_policies") return false;
  if (!context.codes?.includes("BS207")) return false;
  const object = lintObject(lint);
  if (!object) return false;
  const table = exposed(context).find(
    (candidate) =>
      candidate.schema === object.schema && candidate.name === object.name,
  );
  return table !== undefined && permissiveOverlaps(table).length > 0;
}

/**
 * `db.x.aggregate(`, an `_sum:`/`_avg:`/`_min:`/`_max:` include or a list
 * with `facetCounts: true`.
 */
const AGGREGATE_USE =
  /\.aggregate\(|\b_(?:sum|avg|min|max)\s*:\s*\{|\bfacetCounts\s*:\s*true\b/;

/**
 * A policy that reads memberships or the tenant claim: `is_member(...)`,
 * `current_tenant_id()`, `memberships`, PermDock's `permitted_*_ids()`.
 */
const TENANT_HELPER = /member|tenant|current_org|org_id|permitted_\w+_ids/i;

/** A foreign key to the tenant table itself, whose own policies are usually read-only. */
const TENANT_COLUMN = /^(?:org|organization|tenant|team|workspace|account)_id$/;

const COMMANDS = ["select", "insert", "update", "delete"] as const;

const MFA_FACTORS = /\bauth\.\s*"?mfa_factors\b/i;

const OWN_RULES: readonly Rule[] = [
  advisorRule(
    "BS100",
    "security",
    "Supabase security advisor",
    "Findings from the Security Advisor (splinter): RLS disabled in exposed schemas, RLS without policies, mutable search_path, security definer functions callable by anon, exposed auth.users and more. Hosted projects use the Management API; local stacks and --db-url run the pinned splinter.sql.",
  ),
  {
    code: "BS103",
    severity: "error",
    title: "Policy allows anonymous writes",
    description:
      "A permissive policy with `true` for anon or public lets anyone insert, update or delete rows.",
    check: (context) =>
      exposed(context).flatMap((table) =>
        table.policies
          .filter(
            (policy) =>
              policy.permissive &&
              writes(policy) &&
              publicRoles(policy) &&
              (isTrue(policy.using) || isTrue(policy.check)),
          )
          .map((policy) => ({
            message: `Policy "${policy.name}" on ${qualified(table)} allows ${policy.command} for ${policy.roles.join(", ") || "public"} with \`true\`.`,
            target: `${qualified(table)}.${policy.name}`,
            object: policyObject(table, policy),
          })),
      ),
  },
  {
    code: "BS106",
    severity: "error",
    title: "Table not granted to the Data API",
    description:
      "Supabase no longer grants new tables to anon and authenticated. Without a grant, every Data API request fails with 42501 before RLS runs. Tables in `expose` need the privileges listed there; other tables need `select` for authenticated.",
    check: (context) => {
      const auto = context.configToml
        ? tomlGet(context.configToml.document, [
            "api",
            "auto_expose_new_tables",
          ])
        : undefined;
      const note =
        auto === false || auto === "false"
          ? " config.toml sets [api] auto_expose_new_tables = false, so new tables start without grants."
          : "";
      return exposed(context).flatMap((table) => {
        if (context.config.tables[table.name]?.exclude) return [];
        const wanted = context.config.expose[qualified(table)] ??
          context.config.expose[table.name] ?? {
            anon: [],
            authenticated: ["select" as const],
          };
        const granted = (role: string): Set<string> =>
          new Set(
            table.grants
              .filter((grant) => grant.role === role || grant.role === "PUBLIC")
              .flatMap((grant) =>
                grant.privileges.map((privilege) => privilege.toLowerCase()),
              ),
          );
        return (["anon", "authenticated"] as const).flatMap((role) => {
          const have = granted(role);
          const missing = wanted[role].filter(
            (privilege) => !have.has(privilege),
          );
          if (missing.length === 0) return [];
          return [
            {
              message: `${role} has no ${missing.join(", ")} on ${qualified(table)}, so the Data API answers 42501. Add it to \`expose\` and run \`better-supabase sql add grants\`, or run \`grant ${missing.join(", ")} on table ${qualified(table)} to ${role};\`.${note}`,
              target: `${qualified(table)}:${role}`,
              object: tableObject(table),
            },
          ];
        });
      });
    },
  },
  {
    code: "BS107",
    severity: "warning",
    title: "Tenant table without a policy for every command",
    description:
      "A tenant-scoped table with policies for some commands but not all four denies the rest silently: an update or delete then affects 0 rows without an error. Add the missing policies, or a restrictive one, so the intent is explicit, and test it with `expectTenantIsolation`.",
    check: (context) => {
      const column = context.config.plugins.tenant?.column;
      const tables = exposed(context);
      const roots = new Set(
        tables.flatMap((table) =>
          table.foreignKeys
            .filter(
              (key) =>
                key.columns.length === 1 &&
                (column === undefined
                  ? TENANT_COLUMN.test(key.columns[0]!)
                  : key.columns[0] === column),
            )
            .map((key) => `${key.refSchema}.${key.refTable}`),
        ),
      );
      return tables.flatMap((table) => {
        if (table.kind !== "table" || !table.rls) return [];
        if (roots.has(qualified(table))) return [];
        if (context.config.tables[table.name]?.exclude) return [];
        const granting = table.policies.filter(
          (policy) =>
            policy.permissive &&
            policy.roles.some((role) =>
              ["authenticated", "public"].includes(role),
            ),
        );
        if (granting.length === 0) return [];
        const scoped =
          (column !== undefined &&
            table.columns.some((entry) => entry.name === column)) ||
          granting.some((policy) =>
            TENANT_HELPER.test(
              [
                policy.using ?? "",
                policy.check ?? "",
                ...(policy.functions ?? []),
              ].join(" "),
            ),
          );
        if (!scoped) return [];
        const covered = new Set(
          granting.flatMap((policy) =>
            policy.command === "all" ? COMMANDS : [policy.command],
          ),
        );
        const missing = COMMANDS.filter((command) => !covered.has(command));
        if (missing.length === 0) return [];
        return [
          {
            message: `${qualified(table)} is tenant-scoped but has no ${missing.join(", ")} policy for authenticated, so ${missing.join(" and ")} silently match no rows. Add the policies, or state the intent with a restrictive \`using (false)\` policy.`,
            target: qualified(table),
            object: tableObject(table),
          },
        ];
      });
    },
  },
  {
    code: "BS108",
    severity: "error",
    title: "Policy reads auth.mfa_factors directly",
    description:
      "`authenticated` has no access to `auth.mfa_factors`, so a policy that reads it fails every request with 42501. Check the factor in a `security definer` function such as `better_supabase.mfa_satisfied()` from the `mfa` kit module.",
    check: (context) =>
      exposed(context).flatMap((table) =>
        table.policies
          .filter((policy) =>
            MFA_FACTORS.test(`${policy.using ?? ""} ${policy.check ?? ""}`),
          )
          .map((policy) => ({
            message: `Policy "${policy.name}" on ${qualified(table)} reads auth.mfa_factors, which authenticated can't select, so every request fails with 42501. Use \`(select better_supabase.mfa_satisfied())\` from \`better-supabase sql add mfa\` instead.`,
            target: `${qualified(table)}.${policy.name}`,
            object: policyObject(table, policy),
          })),
      ),
  },
  advisorRule(
    "BS200",
    "performance",
    "Supabase performance advisor",
    "Findings from the Performance Advisor (splinter): unindexed foreign keys, auth calls re-evaluated per row in policies, multiple permissive policies, unused and duplicate indexes and more.",
    coveredByBS207,
  ),
  {
    code: "BS204",
    severity: "warning",
    title: "Tenant column without an index",
    description:
      "The tenant plugin and tenant policies filter every query on this column.",
    check: (context) => {
      const tenant = context.config.plugins.tenant;
      if (!tenant) return [];
      return exposed(context)
        .filter(
          (table) =>
            table.columns.some((column) => column.name === tenant.column) &&
            !table.indexes.some(
              (index) => !index.partial && index.columns[0] === tenant.column,
            ),
        )
        .map((table) => ({
          message: `${qualified(table)}.${tenant.column} has no index starting with it.`,
          target: `${qualified(table)}.${tenant.column}`,
          object: tableObject(table),
        }));
    },
  },
  {
    code: "BS210",
    severity: "warning",
    title: "Aggregates used while PostgREST disables them",
    description:
      "PostgREST rejects `count()`, `sum()` and the other aggregates with PGRST123 unless `pgrst.db_aggregates_enabled` is on for the authenticator role. `aggregate()`, `_sum`/`_avg`/`_min`/`_max` includes and list `facetCounts` need it; `better-supabase/postgres` does not.",
    check: (context) => {
      const settings = context.snapshot.extras.roleSettings;
      if (!settings) return [];
      const enabled =
        settings["authenticator"]?.["pgrst.db_aggregates_enabled"];
      if (enabled === "true" || enabled === "on") return [];
      for (const file of context.sources) {
        const line = lineOf(file.text, AGGREGATE_USE);
        if (line === undefined) continue;
        return [
          {
            message: `${file.path} uses aggregates, but PostgREST has them off, so these requests fail with PGRST123. Run \`alter role authenticator set pgrst.db_aggregates_enabled = 'true'; notify pgrst, 'reload config';\` in a migration.`,
            target: "authenticator:pgrst.db_aggregates_enabled",
            location: { file: file.path, line },
          },
        ];
      }
      return [];
    },
  },
  {
    code: "BS301",
    severity: "warning",
    title: "Soft delete hidden by a select policy",
    description:
      "PostgREST re-reads updated rows through the select policy. If it hides deleted rows, soft-deleting fails with an RLS error unless the update returns nothing.",
    check: (context) => {
      const softDelete = context.config.plugins.softDelete;
      if (!softDelete) return [];
      return exposed(context).flatMap((table) => {
        if (!table.columns.some((column) => column.name === softDelete.column))
          return [];
        return table.policies
          .filter(
            (policy) =>
              (policy.command === "select" || policy.command === "all") &&
              new RegExp(`\\b${softDelete.column}\\b\\s+IS\\s+NULL`, "i").test(
                policy.using ?? "",
              ),
          )
          .map((policy) => ({
            message: `Policy "${policy.name}" on ${qualified(table)} hides rows where ${softDelete.column} is set, so \`softDelete()\` can't read the row back. Filter deleted rows in queries (the plugin does) instead of in the policy.`,
            target: `${qualified(table)}.${policy.name}`,
            object: policyObject(table, policy),
          }));
      });
    },
  },
  {
    code: "BS302",
    severity: "warning",
    title: "Bucket differs from the config",
    description:
      "A bucket in `buckets` is missing or has different settings in the database.",
    check: (context) =>
      Object.entries(context.config.buckets).flatMap(([name, bucket]) => {
        const id =
          bucket.id ??
          name.replaceAll(/[A-Z]/g, (char) => `-${char.toLowerCase()}`);
        const defined = defineBucket({
          id,
          path: bucket.path,
          ...(bucket.public === undefined ? {} : { public: bucket.public }),
          ...(bucket.fileSizeLimit === undefined
            ? {}
            : { fileSizeLimit: bucket.fileSizeLimit }),
          ...(bucket.allowedMimeTypes === undefined
            ? {}
            : { allowedMimeTypes: bucket.allowedMimeTypes }),
        });
        const actual = catalogOf(context).buckets.find(
          (entry) => entry.id === id,
        );
        const inDatabase = defined.drift(actual).map((drift) => ({
          message: `Bucket ${id}: ${drift.message}`,
          target: `storage.buckets.${id}`,
        }));
        const toml = context.configToml;
        const declared = toml
          ? tomlGet(toml.document, ["storage", "buckets", id])
          : undefined;
        if (
          !toml ||
          !declared ||
          typeof declared !== "object" ||
          Array.isArray(declared)
        )
          return inDatabase;
        // SAFETY: the check above narrows declared to a TOML table.
        const entry = declared as Readonly<Record<string, TomlValue>>;
        const size = entry["file_size_limit"];
        const mimes = entry["allowed_mime_types"];
        const line = lineOf(
          toml.text,
          new RegExp(
            `^\\[storage\\.buckets\\.${id.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\]`,
          ),
        );
        const inToml = defined
          .drift({
            public: entry["public"] === true,
            fileSizeLimit:
              typeof size === "string" || typeof size === "number"
                ? parseSize(size)
                : null,
            allowedMimeTypes: Array.isArray(mimes) ? mimes.map(String) : null,
          })
          .map((drift) => ({
            message: `${toml.path} [storage.buckets.${id}]: ${drift.message.replace(`Bucket "${id}" `, "")}`,
            target: `[storage.buckets.${id}]`,
            ...(line ? { location: { file: toml.path, line } } : {}),
          }));
        return [...inDatabase, ...inToml];
      }),
  },
  {
    code: "BS303",
    severity: "error",
    title: "Generated code is out of date",
    description:
      "The generated module no longer matches the database, so types and metadata are wrong. Same check as `gen --check`.",
    check: async (context) => {
      const stale: FindingInput[] = [];
      for (const file of await renderFiles(context.config, context.snapshot)) {
        const current = await readFile(
          resolve(context.config.root, file.path),
          "utf8",
        ).catch(() => undefined);
        if (current !== file.contents) {
          stale.push({
            message: `${file.path} is ${current === undefined ? "missing" : "out of date"}. Run \`better-supabase gen\`.`,
            target: file.path,
            ...(current === undefined
              ? {}
              : { location: { file: file.path, line: 1 } }),
          });
        }
      }
      return stale;
    },
  },
  {
    code: "BS304",
    severity: "warning",
    title: "SQL kit files are out of date",
    description:
      "A module listed in `sql.kit` differs from the version in this release. Same check as `sql sync --check`.",
    check: async (context) => {
      if (context.config.sql.kit.length === 0) return [];
      const stale: FindingInput[] = [];
      const readSets = context.readSets;
      const skipped = readSets !== undefined && "skipped" in readSets;
      for (const file of renderKit(
        context.config.sql.kit,
        kitLayout(
          context.config,
          context.config.sql.testsDir,
          skipped ? [] : readSets,
          entitlementsKit(context),
        ),
      )) {
        if (skipped && file.module === "read-sets") continue;
        const current = await readFile(
          resolve(context.config.root, file.path),
          "utf8",
        ).catch(() => undefined);
        if (sameKitFile(current, file.contents)) continue;
        stale.push({
          message: `${file.path} (${file.module}) is ${current === undefined ? "missing" : "out of date"}. Run \`better-supabase sql sync\`, then \`supabase db diff\`.`,
          target: file.path,
          ...(current === undefined
            ? {}
            : { location: { file: file.path, line: 1 } }),
        });
      }
      return stale;
    },
  },
  {
    code: "BS305",
    severity: "warning",
    title: "Live query table without change broadcasts",
    description:
      "A table in `realtime.tables` has no `bs_realtime` trigger, so live queries never hear about its changes.",
    check: (context) => {
      const tables = catalogOf(context).tables;
      return context.config.realtime.tables.flatMap((name) => {
        const table = tables.find(
          (entry) => entry.name === name || qualified(entry) === name,
        );
        if (!table) {
          return [
            {
              message: `realtime.tables lists "${name}", which doesn't exist.`,
              target: name,
            },
          ];
        }
        if (
          table.triggers.some((trigger) =>
            trigger.name.startsWith("bs_realtime"),
          )
        )
          return [];
        return [
          {
            message: `${qualified(table)} is in realtime.tables but has no broadcast trigger. Run \`better-supabase sql add realtime-tables\`, then \`supabase db diff\`.`,
            target: qualified(table),
            object: tableObject(table),
          },
        ];
      });
    },
  },
  {
    code: "BS306",
    severity: "warning",
    title: "Realtime delete events without keys",
    description:
      "Tables in the `supabase_realtime` publication send the replica identity of deleted rows. With `nothing`, or `default` without a primary key, delete events carry no keys and clients cannot tell which row went away.",
    check: (context) => {
      const published = new Set(catalogOf(context).realtime);
      return catalogOf(context)
        .tables.filter(
          (table) =>
            published.has(qualified(table)) &&
            (table.replicaIdentity === "NOTHING" ||
              (table.replicaIdentity === "DEFAULT" &&
                table.primaryKey.length === 0)),
        )
        .map((table) => ({
          message: `${qualified(table)} is published to Realtime with replica identity ${table.replicaIdentity?.toLowerCase() ?? "unknown"}${table.primaryKey.length === 0 ? " and no primary key" : ""}. Add a primary key or run \`alter table ${qualified(table)} replica identity full\`.`,
          target: qualified(table),
          object: tableObject(table),
        }));
    },
  },
  {
    code: "BS401",
    severity: "warning",
    title: "Refresh token reuse interval is 0",
    description:
      "Server instances refreshing the same session at once need a reuse interval, or all but one of them sign the user out.",
    check: (context) => {
      if (!context.configToml) return [];
      const rotation = authSetting(context, "enable_refresh_token_rotation");
      const interval = authSetting(context, "refresh_token_reuse_interval");
      if (
        rotation === false ||
        rotation === "false" ||
        interval === undefined ||
        Number(interval) > 0
      )
        return [];
      const location = tomlLocation(context, "refresh_token_reuse_interval");
      return [
        {
          message:
            "refresh_token_reuse_interval = 0 with refresh token rotation. Use 10 (the Supabase default) so concurrent refreshes succeed.",
          target: "[auth] refresh_token_reuse_interval",
          ...(location ? { location } : {}),
        },
      ];
    },
  },
  {
    code: "BS402",
    severity: "info",
    title: "Long access token lifetime",
    description:
      "Tokens are verified locally without an auth call, so a revoked session stays valid until the token expires.",
    check: (context) => {
      if (!context.configToml) return [];
      const expiry = Number(authSetting(context, "jwt_expiry") ?? 3600);
      if (expiry <= 3600) return [];
      const location = tomlLocation(context, "jwt_expiry");
      return [
        {
          message: `jwt_expiry is ${expiry}s. Keep it at 3600 or less; sessions refresh in the proxy.`,
          target: "[auth] jwt_expiry",
          ...(location ? { location } : {}),
        },
      ];
    },
  },
  {
    code: "BS403",
    severity: "info",
    title: "Local stack signs tokens with a shared secret",
    description:
      "Hosted projects sign with asymmetric keys. Using the same locally means local tokens verify through JWKS just like production.",
    check: (context) => {
      if (!context.configToml || authSetting(context, "signing_keys_path"))
        return [];
      const location = tomlLocation(context, "signing_keys_path");
      return [
        {
          message:
            "No [auth] signing_keys_path. Run `better-supabase keys` to sign local tokens with ES256.",
          target: "[auth] signing_keys_path",
          ...(location ? { location } : {}),
        },
      ];
    },
  },
  {
    code: "BS406",
    severity: "warning",
    title: "Foreign key to auth.users blocks account deletion",
    description:
      'A foreign key to `auth.users` with `no action` or `restrict` makes `auth.admin.deleteUser` (and `deleteAccount`) fail with "Database error deleting user" while the user has rows. Use `on delete cascade` for data the user owns, or `on delete set null` for records that outlive them.',
    check: (context) =>
      catalogOf(context).tables.flatMap((table) =>
        table.schema === "auth"
          ? []
          : table.foreignKeys
              .filter(
                (key) =>
                  key.refSchema === "auth" &&
                  key.refTable === "users" &&
                  (key.onDelete === "no action" || key.onDelete === "restrict"),
              )
              .map((key) => ({
                message: `${qualified(table)}.${key.name} (${key.columns.join(", ")}) references auth.users with on delete ${key.onDelete}. Deleting the user fails while rows point at it; use on delete cascade or set null.`,
                target: `${qualified(table)}.${key.name}`,
                object: tableObject(table),
              })),
      ),
  },
  {
    code: "BS501",
    severity: "error",
    title: "Secret in a browser variable",
    description:
      "Variables with a public prefix are bundled into client code. A secret key there gives every visitor full access.",
    check: (context) =>
      context.envFiles.flatMap((file) =>
        envEntries(file)
          .filter(
            (entry) =>
              PUBLIC_PREFIXES.some((prefix) => entry.key.startsWith(prefix)) &&
              (entry.value.startsWith("sb_secret_") ||
                /SECRET|SERVICE_ROLE/.test(entry.key)),
          )
          .map((entry) => ({
            message: `${entry.key} in ${file.path} is exposed to the browser but holds a secret. Rename it without the public prefix and rotate the key.`,
            target: `${file.path}:${entry.key}`,
            location: { file: file.path, line: entry.line },
          })),
      ),
  },
  {
    code: "BS502",
    severity: "warning",
    title: "Env file with secrets is not ignored by git",
    description:
      "Env files holding a secret key or database password should never be committed.",
    check: (context) => {
      const patterns = context.gitignore
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0 && !line.startsWith("#"));
      const ignored = (path: string): boolean =>
        patterns.some((pattern) => {
          const source = pattern
            .replace(/^\//, "")
            .replaceAll(/[.+^${}()|[\]\\]/g, "\\$&")
            .replaceAll("*", ".*");
          return (
            new RegExp(`^${source}$`).test(path) ||
            new RegExp(`(^|/)${source}$`).test(path)
          );
        });
      return context.envFiles.flatMap((file) => {
        const secret = envEntries(file).find(
          (entry) =>
            entry.value.startsWith("sb_secret_") ||
            /SECRET_KEY|SERVICE_ROLE|DB_URL|DATABASE_URL/.test(entry.key),
        );
        if (!secret || ignored(file.path) || file.path.endsWith(".example"))
          return [];
        return [
          {
            message: `${file.path} contains ${secret.key} but isn't in .gitignore.`,
            target: file.path,
            location: { file: file.path, line: secret.line },
          },
        ];
      });
    },
  },
];

export const RULES: readonly Rule[] = [
  ...OWN_RULES,
  ...RLS_RULES,
  ...HOOK_RULES,
  ...PERMDOCK_RULES,
  ...LIVE_RULES,
].sort((a, b) => a.code.localeCompare(b.code));

export const RULE_CODES: readonly string[] = RULES.map((rule) => rule.code);

export async function runRules(
  context: DoctorContext,
  rules: readonly Rule[] = RULES,
): Promise<Finding[]> {
  const findings: Finding[] = [];
  const scoped = { ...context, codes: rules.map((rule) => rule.code) };
  for (const rule of rules) {
    for (const input of await rule.check(scoped)) {
      findings.push({
        code: rule.code,
        severity: rule.severity,
        title: rule.title,
        help: `${DOCS_URL}#${rule.code.toLowerCase()}`,
        ...input,
      });
    }
  }
  return findings;
}
