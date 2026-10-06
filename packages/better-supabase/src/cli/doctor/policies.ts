import type { CatalogPolicy, CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  appliesTo,
  COMMANDS,
  escape,
  functionBody,
  functionObject,
  policyHelpers,
  withoutStrings,
} from "./rls.ts";
import {
  catalogOf,
  exposed,
  policyObject,
  qualified,
  tableObject,
} from "./shared.ts";

const AUTH_ROLE = /\bauth"?\s*\.\s*"?role"?\s*\(\s*\)/i;

/** A check of who is calling: the JWT, the user id, or the session role. */
const CALLER_CHECK =
  /\bauth"?\s*\.\s*"?(?:uid|jwt)"?\s*\(|request\.jwt|\b(?:current_user|session_user|current_role)\b|has_organization_role|member_organization_ids/i;

const USER_METADATA = /\buser_metadata\b/i;

/** Privileges an API role never needs on a table. */
const NEEDLESS = ["TRUNCATE", "REFERENCES", "TRIGGER"] as const;

const policyText = (policy: CatalogPolicy): string =>
  withoutStrings(`${policy.using ?? ""} ${policy.check ?? ""}`);

/** A permissive policy lets `role` run `command` on the table. */
const allows = (
  table: CatalogTable,
  command: (typeof COMMANDS)[number],
  role: string,
): boolean =>
  table.policies.some(
    (policy) =>
      policy.permissive &&
      (policy.command === "all" || policy.command === command) &&
      appliesTo(policy, role),
  );

/** Policy commands on `storage.objects` the SQL files create, by policy name. */
function storagePolicies(context: DoctorContext): Map<string, string> {
  const commands = new Map<string, string>();
  const pattern =
    /create\s+policy\s+("(?:[^"]|"")+"|\S+)\s+on\s+"?storage"?\s*\.\s*"?objects"?\b([^;]*)/gi;
  for (const file of context.sqlFiles ?? []) {
    for (const match of withoutStrings(file.text).matchAll(pattern)) {
      const name = match[1]!;
      if (commands.has(name)) continue;
      const command = /\bfor\s+(select|insert|update|delete|all)\b/i.exec(
        match[2]!,
      )?.[1];
      commands.set(name, command?.toLowerCase() ?? "all");
    }
  }
  return commands;
}

export const POLICY_RULES: readonly Rule[] = [
  {
    code: "BS109",
    severity: "warning",
    title: "auth.role() in a policy or function",
    description:
      "Supabase deprecated `auth.role()`. Scope the policy with `to authenticated`, or read the claim with `(select auth.jwt() ->> 'role')`.",
    check: (context) => {
      const findings: FindingInput[] = [];
      for (const table of catalogOf(context).tables) {
        for (const policy of table.policies) {
          if (!AUTH_ROLE.test(policyText(policy))) continue;
          findings.push({
            message: `Policy "${policy.name}" on ${qualified(table)} calls auth.role(), which Supabase deprecated. Use \`to authenticated\` on the policy, or \`(select auth.jwt() ->> 'role')\`.`,
            target: `${qualified(table)}.${policy.name}`,
            object: policyObject(table, policy),
          });
        }
      }
      const bodies = new Map(policyHelpers(context));
      for (const fn of context.snapshot.generator.functions) {
        if (!context.config.schemas.includes(fn.schema) || !fn.definition)
          continue;
        bodies.set(`${fn.schema}.${fn.name}`, withoutStrings(fn.definition));
      }
      for (const [name, body] of bodies) {
        if (!AUTH_ROLE.test(body)) continue;
        const dot = name.indexOf(".");
        findings.push({
          message: `${name} calls auth.role(), which Supabase deprecated. Read \`auth.jwt() ->> 'role'\` instead.`,
          target: name,
          object: {
            kind: "function",
            schema: name.slice(0, dot),
            name: name.slice(dot + 1),
          },
        });
      }
      return findings;
    },
  },
  {
    code: "BS110",
    severity: "warning",
    title: "Update policy without a select policy or with check",
    description:
      "An update has to find the rows first, so without a select policy for the same role it matches no rows and reports success. Without `with check`, Postgres checks the new row against `using`, which hides whether moving a row to another owner or tenant is allowed.",
    check: (context) =>
      exposed(context).flatMap((table) => {
        if (!table.rls) return [];
        return table.policies.flatMap((policy): FindingInput[] => {
          if (!policy.permissive || policy.command !== "update") return [];
          const roles =
            policy.roles.length === 0 || policy.roles.includes("public")
              ? ["anon", "authenticated"]
              : policy.roles;
          const blind = roles.filter((role) => !allows(table, "select", role));
          const target = `${qualified(table)}.${policy.name}`;
          if (blind.length > 0)
            return [
              {
                message: `Policy "${policy.name}" on ${qualified(table)} allows update for ${blind.join(", ")}, but no select policy does, so updates match no rows without an error. Add a select policy for ${blind.join(", ")}.`,
                target,
                object: policyObject(table, policy),
              },
            ];
          if (policy.check !== null) return [];
          return [
            {
              severity: "info",
              message: `Policy "${policy.name}" on ${qualified(table)} has no \`with check\`, so Postgres checks updated rows against \`using\`. State the rule for the new row with \`with check (...)\`.`,
              target,
              object: policyObject(table, policy),
            },
          ];
        });
      }),
  },
  {
    code: "BS111",
    severity: "warning",
    title: "API roles hold privileges they don't use",
    description:
      "`anon` and `authenticated` never need `truncate`, `references` or `trigger`, and `truncate` skips RLS. A grant to `anon` on a table no policy opens to it does nothing except list the table in the Data API schema.",
    check: (context) =>
      exposed(context).flatMap((table) => {
        if (table.kind !== "table") return [];
        const findings: FindingInput[] = [];
        for (const role of ["anon", "authenticated"] as const) {
          const privileges = new Set(
            table.grants
              .filter((grant) => grant.role === role)
              .flatMap((grant) => grant.privileges),
          );
          const needless = NEEDLESS.filter((privilege) =>
            privileges.has(privilege),
          );
          if (needless.length > 0)
            findings.push({
              message: `${role} has ${needless.join(", ").toLowerCase()} on ${qualified(table)}. \`truncate\` bypasses RLS. Run \`revoke ${needless.join(", ").toLowerCase()} on table ${qualified(table)} from ${role};\`.`,
              target: `${qualified(table)}:${role}`,
              object: tableObject(table),
            });
          if (role !== "anon" || !table.rls) continue;
          const unused = COMMANDS.filter(
            (command) =>
              privileges.has(command.toUpperCase()) &&
              !allows(table, command, role),
          );
          if (unused.length > 0)
            findings.push({
              severity: "info",
              message: `anon has ${unused.join(", ")} on ${qualified(table)}, but no policy allows it for anon, so the grant only lists the table in the Data API schema. Run \`revoke ${unused.join(", ")} on table ${qualified(table)} from anon;\`.`,
              target: `${qualified(table)}:anon:unused`,
              object: tableObject(table),
            });
        }
        return findings;
      }),
  },
  {
    code: "BS112",
    severity: "warning",
    title: "Exposed security definer function that doesn't check the caller",
    description:
      "A `security definer` function in an exposed schema runs as its owner, past RLS, and the Data API serves it at `/rpc`. When anon or authenticated may execute it and its body never reads `auth.uid()` or `auth.jwt()`, any caller gets the owner's access. Check the caller, revoke `execute`, or move it to a schema the API doesn't expose.",
    check: (context) =>
      (context.snapshot.extras.functions ?? []).flatMap(
        (fn): FindingInput[] => {
          if (
            !fn.securityDefiner ||
            !context.config.schemas.includes(fn.schema)
          )
            return [];
          const callers = fn.execute ?? [];
          if (callers.length === 0) return [];
          const body = functionBody(context, fn.schema, fn.name);
          if (body === undefined || CALLER_CHECK.test(body)) return [];
          return [
            {
              message: `${fn.schema}.${fn.name}(${fn.signature}) is security definer, ${callers.join(" and ")} may execute it through /rpc, and it never checks auth.uid() or auth.jwt(). Check the caller, run \`revoke execute on function ${fn.schema}.${fn.name}(${fn.signature}) from ${callers.join(", ")};\`, or move it to a private schema.`,
              target: `${fn.schema}.${fn.name}`,
              object: functionObject(fn),
            },
          ];
        },
      ),
  },
  {
    code: "BS113",
    severity: "info",
    title: "Storage upload policy without the upsert policies",
    description:
      "An upload with `upsert: true` (`x-upsert`) needs `select` and `update` policies on `storage.objects` besides `insert`; without them, replacing an existing file fails with a 403. Doctor reads the policies in `supabase/schemas` and the migrations.",
    check: (context) => {
      const commands = new Set(storagePolicies(context).values());
      if (!commands.has("insert") || commands.has("all")) return [];
      const missing = (["select", "update"] as const).filter(
        (command) => !commands.has(command),
      );
      if (missing.length === 0) return [];
      return [
        {
          message: `storage.objects has an insert policy but no ${missing.join(" or ")} policy, so uploads with \`upsert: true\` fail with 403 when the file exists. Add ${missing.join(" and ")} policies with the same bucket and path check.`,
          target: "storage.objects",
        },
      ];
    },
  },
  {
    code: "BS114",
    severity: "error",
    title: "Policy helper reads user_metadata",
    description:
      "Users can change their own `raw_user_meta_data` with `auth.updateUser()`, so a helper that reads `user_metadata` to decide access lets them grant themselves rights. Read `app_metadata`, which only the service role can write. Splinter's `rls_references_user_metadata` covers the policy text; this covers the functions policies call.",
    check: (context) =>
      [...policyHelpers(context).keys()].flatMap((name): FindingInput[] => {
        const dot = name.indexOf(".");
        // The claim is always a string literal, which the helper bodies blank out.
        const body = functionBody(
          context,
          name.slice(0, dot),
          name.slice(dot + 1),
        );
        if (!body || !USER_METADATA.test(body)) return [];
        return [
          {
            message: `${name} reads user_metadata, which users can write themselves, and policies call it. Read \`auth.jwt() -> 'app_metadata'\` instead.`,
            target: name,
            object: {
              kind: "function",
              schema: name.slice(0, dot),
              name: name.slice(dot + 1),
            },
          },
        ];
      }),
  },
  {
    code: "BS215",
    severity: "warning",
    title: "Policy calls a helper per row that could run once",
    description:
      "A call such as `current_tenant_id()` takes no column of the row, so its result is the same for every row. Wrapped as `(select current_tenant_id())`, Postgres runs it once per statement as an InitPlan. Splinter's `auth_rls_initplan` covers `auth.*` calls; this covers your own helpers.",
    check: (context) => {
      const volatility = new Map(
        (context.snapshot.extras.functions ?? []).map((fn) => [
          `${fn.schema}.${fn.name}`,
          fn.volatility,
        ]),
      );
      return exposed(context).flatMap((table) => {
        if (!table.rls) return [];
        return table.policies.flatMap((policy): FindingInput[] => {
          const text = policyText(policy);
          const bare = (policy.functions ?? []).filter((name) => {
            const dot = name.indexOf(".");
            const schema = name.slice(0, dot);
            if (schema === "auth" || volatility.get(name) === "immutable")
              return false;
            return new RegExp(
              `(?<!\\bselect\\s+)(?<![\\w."])(?:"?${escape(schema)}"?\\.)?"?${escape(name.slice(dot + 1))}"?\\s*\\(\\s*\\)`,
              "i",
            ).test(text);
          });
          if (bare.length === 0) return [];
          return [
            {
              message: `Policy "${policy.name}" on ${qualified(table)} calls ${bare.map((name) => `${name}()`).join(", ")} without \`(select ...)\`, so it runs once per row. Write \`(select ${bare[0]}())\`.`,
              target: `${qualified(table)}.${policy.name}`,
              object: policyObject(table, policy),
            },
          ];
        });
      });
    },
  },
];
