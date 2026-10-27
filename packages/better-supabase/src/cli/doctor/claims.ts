import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { providerLabel } from "../authorization.ts";
import { lineOf } from "./shared.ts";

const PERMISSIONS_AUTHORIZER = /\bpermissionsAuthorizer\s*\(/;

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

export const CLAIM_RULES: readonly Rule[] = [
  {
    code: "BS419",
    severity: "warning",
    title: "Permission keys the token leaves out",
    description:
      "The `permissions` claim carries only the keys the authorization provider marks `sqlComplete: true`, because the SQL functions can't decide the rest. `permissionsAuthorizer` reads that claim, so a check for another key finds nothing in the token and is denied unless its `load` option asks the database. Doctor reports app files that call `permissionsAuthorizer(` while `authorization.permissions` is missing or has keys without `sqlComplete`.",
    check: claimGaps,
  },
];
