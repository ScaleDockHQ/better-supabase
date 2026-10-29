import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { providerLabel } from "../authorization.ts";
import { configuredHooks, isProviderHook, signatureOf } from "./hooks.ts";
import { catalogOf, lineOf } from "./shared.ts";

const PERMISSIONS_AUTHORIZER = /\bpermissionsAuthorizer\s*\(/;

const MODULE_VERSION = /better_supabase\s*\.\s*authz_version\s*\(/i;

/**
 * Files that build `permissionsAuthorizer` while the provider leaves keys
 * without `sqlComplete` (BS419).
 */
function claimGaps(context: DoctorContext): FindingInput[] {
  const provider = context.config.authorization;

  if (!provider) {
    return [];
  }

  const incomplete = (provider.permissions ?? [])
    .filter((permission) => permission.sqlComplete !== true)
    .map((permission) => permission.key);

  const unlisted = provider.permissions === undefined;

  if (!unlisted && incomplete.length === 0) {
    return [];
  }

  const missing = unlisted
    ? "lists no permissions, so the permissions claim is empty"
    : `doesn't mark ${incomplete.join(", ")} sqlComplete, so the permissions claim leaves ${incomplete.length === 1 ? "it" : "them"} out`;

  return context.sources.flatMap((file) => {
    if (!PERMISSIONS_AUTHORIZER.test(file.text)) {
      return [];
    }

    return [
      {
        message: `${file.path} decides with permissionsAuthorizer, but ${providerLabel(provider)} ${missing}. Those checks are denied unless \`load\` asks the database. Mark the keys sqlComplete when the SQL functions answer for them, or pass \`load\` (my_permissions).`,
        target: `${file.path}:permissionsAuthorizer`,
        location: {
          file: file.path,
          line: lineOf(file.text, PERMISSIONS_AUTHORIZER) ?? 1,
        },
      },
    ];
  });
}

/**
 * A second version source next to a provider that keeps the versions: the
 * sessions module's table, or an app hook reading it (BS420).
 */
function versionSources(context: DoctorContext): FindingInput[] {
  const provider = context.config.authorization;
  const versions = provider?.versions;

  if (!provider || !versions) {
    return [];
  }

  const label = providerLabel(provider);
  const findings: FindingInput[] = [];

  const table = catalogOf(context).tables.some(
    (entry) =>
      entry.schema === "better_supabase" &&
      entry.name === "user_authz_versions",
  );

  if (table) {
    findings.push({
      message: `better_supabase.user_authz_versions is in the database, but ${label} keeps the authorization versions in ${versions.function}. Nothing bumps the table any more, so a reader of it sees old versions. Drop it with a migration (\`better-supabase db diff\` writes one once the sessions module no longer renders it).`,
      target: "better_supabase.user_authz_versions",
      object: {
        kind: "table",
        schema: "better_supabase",
        name: "user_authz_versions",
      },
    });
  }

  for (const { config, extras } of configuredHooks(context)) {
    if (config.hook !== "custom_access_token" || !extras) {
      continue;
    }

    for (const fn of extras.functions) {
      if (
        fn.source === undefined ||
        isProviderHook(context, fn) ||
        !MODULE_VERSION.test(fn.source)
      ) {
        continue;
      }

      findings.push({
        message: `${signatureOf(fn)} reads better_supabase.authz_version, but ${label} keeps the authorization versions in ${versions.function}. Tokens would carry a version nothing bumps, so role changes never look newer. Use the provider's hook, or read ${versions.function} instead.`,
        target: signatureOf(fn),
        object: { kind: "function", schema: fn.schema, name: fn.name },
      });
    }
  }

  return findings;
}

export const CLAIM_RULES: readonly Rule[] = [
  {
    code: "BS419",
    severity: "warning",
    title: "Permission keys the token leaves out",
    description:
      "The `permissions` claim carries only the keys the authorization provider marks `sqlComplete: true`, because the SQL functions can't decide the rest. `permissionsAuthorizer` reads that claim, so a check for another key finds nothing in the token and is denied unless its `load` option asks the database. Doctor reports app files that call `permissionsAuthorizer(` while `authorization.permissions` is missing or has keys without `sqlComplete`.",
    check: claimGaps,
  },
  {
    code: "BS420",
    severity: "error",
    title: "A second authorization version source",
    description:
      "When the authorization provider keeps the authorization versions (`authorization.versions`), the sessions module's `authzVersions` option renders no table, trigger or broadcast of its own and reads the provider's function. Doctor reports a `better_supabase.user_authz_versions` table that is still in the database, and a custom access token hook other than the provider's that reads `better_supabase.authz_version(`: either gives tokens and the bootstrap a version nothing bumps, so a role change never looks newer.",
    check: versionSources,
  },
];
