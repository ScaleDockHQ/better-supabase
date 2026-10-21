import type { DoctorContext, FindingInput } from "./rules.ts";

/**
 * Supautils' `reserved_roles` on Supabase. Nobody but a superuser may alter,
 * drop or change the memberships of these.
 */
const RESERVED_ROLES = new Set([
  "supabase_admin",
  "supabase_auth_admin",
  "supabase_storage_admin",
  "supabase_functions_admin",
  "supabase_read_only_user",
  "supabase_realtime_admin",
  "supabase_replication_admin",
  "supabase_etl_admin",
  "dashboard_user",
  "pgbouncer",
]);

/**
 * Reserved roles whose settings (`alter role ... set`) supautils allows
 * changing.
 */
const SETTINGS_ONLY_ROLES = new Set([
  "authenticator",
  "authenticated",
  "anon",
  "service_role",
]);

/**
 * Roles that Supabase's own services log in as. Their statements (PostgREST's
 * schema cache query, Auth and Storage migrations) aren't the app's.
 */
export const PLATFORM_ROLES: ReadonlySet<string> = new Set([
  ...RESERVED_ROLES,
  "authenticator",
]);

/** Comments and string literals blanked, newlines kept so offsets map to lines. */
const sqlCode = (text: string): string =>
  text
    .replaceAll(/\/\*[\s\S]*?\*\//g, (comment) =>
      comment.replaceAll(/[^\n]/g, " "),
    )
    .replaceAll(/--[^\n]*/g, "")
    .replaceAll(/'(?:[^']|'')*'/g, "''");

const roleNames = (list: string): string[] =>
  list
    .split(",")
    .map((name) => name.trim().replaceAll('"', "").toLowerCase())
    .filter((name) => name !== "");

/** Why a statement changes a reserved role, or undefined when it doesn't. */
function reservedRoleChange(statement: string): string | undefined {
  const alter =
    /^\s*(alter|drop)\s+(?:role|user)\s+(?:if\s+exists\s+)?("[^"]+"|\w+)\s*(\w*)/i.exec(
      statement,
    );

  if (alter) {
    const role = roleNames(alter[2]!)[0]!;
    const verb = alter[1]!.toLowerCase();
    const next = alter[3]!.toLowerCase();

    if (RESERVED_ROLES.has(role)) {
      return `${verb}s the reserved role ${role}`;
    }

    if (
      SETTINGS_ONLY_ROLES.has(role) &&
      (verb === "drop" || (next !== "set" && next !== "reset" && next !== "in"))
    ) {
      return `${verb}s the reserved role ${role}; only \`alter role ${role} set ...\` is allowed`;
    }

    return undefined;
  }

  const membership =
    /^\s*(grant|revoke)\s+(?![\s\S]*\bon\b)([\w",\s]+?)\s+(?:to|from)\s+([\w",\s]+?)(?:\s+with\s+\w+\s+option)?\s*$/i.exec(
      statement,
    );

  if (!membership) {
    return undefined;
  }

  const role = [
    ...roleNames(membership[2]!),
    ...roleNames(membership[3]!),
  ].find((name) => RESERVED_ROLES.has(name));

  return role === undefined
    ? undefined
    : `${membership[1]!.toLowerCase()}s a membership of the reserved role ${role}`;
}

/**
 * Where a statement ends, including statements inside `do` blocks and function
 * bodies.
 */
const STATEMENT_BOUNDARY = /;|\$\w*\$|\b(?:begin|then|else|loop)\b/gi;

/** Statements in schema files and migrations that supautils rejects on Supabase. */
export function reservedRoles(context: DoctorContext): FindingInput[] {
  return (context.sqlFiles ?? []).flatMap((file) => {
    const code = sqlCode(file.text);
    const findings: FindingInput[] = [];
    let start = 0;

    for (const end of [...code.matchAll(STATEMENT_BOUNDARY), undefined]) {
      const until = end?.index ?? code.length;
      const statement = code.slice(start, until);
      const reason = reservedRoleChange(statement);

      if (reason !== undefined) {
        const at = start + statement.search(/\S/);
        const line = code.slice(0, at).split("\n").length;
        findings.push({
          message: `${file.path}:${String(line)} ${reason}. supautils rejects it on Supabase, so the migration fails on a hosted project; grant privileges to your own role instead.`,
          target: `${file.path}:${String(line)}`,
          location: { file: file.path, line },
        });
      }

      start = until + (end?.[0].length ?? 0);
    }

    return findings;
  });
}
