import type { Codemod, CodemodResult, ReviewHint } from "./codemod.ts";

import {
  PERMISSION_KEY_RENAMES,
  PERMISSION_KEY_SPLITS,
  RENAMES_CODEMOD,
} from "../blocks/permissions/index.ts";
import { renamed } from "../index.ts";

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Old keys that are also event type patterns (`support.*` matches the
 * `support.started` event), so a string with one is listed, not rewritten.
 */
const AMBIGUOUS = new Set(["support.*", "workflow.*"]);

/**
 * `workflow.*` keys split between `workflows` and `workflow_editor`: which one
 * a string means depends on the block it guards.
 */
const WORKFLOW_SPLIT = new Set([
  "workflow.admin",
  "workflow.read",
  "workflow.run",
]);

const PERMISSION_STRINGS: Readonly<Record<string, string>> = Object.fromEntries(
  Object.entries(PERMISSION_KEY_RENAMES).filter(
    ([old]) => !AMBIGUOUS.has(old) && !WORKFLOW_SPLIT.has(old),
  ),
);

const quoted = (keys: Iterable<string>): RegExp =>
  new RegExp(`["'\`](?:${[...keys].map(escapeRegExp).join("|")})["'\`]`);

const REVIEW_0_46: readonly ReviewHint[] = [
  {
    pattern: quoted(
      Object.keys(PERMISSION_KEY_SPLITS).filter((key) => key.startsWith("ai.")),
    ),
    message:
      "The `ai.*` keys split into one area per AI block (agents, ai_files, ai_keys, ai_schedules, connectors, knowledge, memory): use the key of the block this check guards",
  },
  {
    pattern: quoted(WORKFLOW_SPLIT),
    message:
      "`workflow.*` keys split: the workflows block checks `workflows.read`, `workflows.run` and `workflows.manage`, the workflow editor `workflow_editor.read`, `workflow_editor.run` and `workflow_editor.manage`",
  },
  {
    pattern: quoted(AMBIGUOUS),
    message:
      "A permission wildcard and an event pattern look the same here: as a permission, `support.*` is now `impersonation.*` and `workflow.*` is `workflows.*` plus `workflow_editor.*`; as an event pattern, leave it",
  },
  {
    pattern: quoted(["members.invite", "members.*"]),
    message:
      "The waitlist block checks `waitlist.invite` now, not `members.invite`: grant it next to `members.invite` where a role admits waitlist entries",
  },
  {
    pattern: quoted(["organization.export", "organization.*"]),
    message:
      "Data exports check `data_lifecycle.export` now, not `organization.export`: grant it where a role grants `organization.*`",
  },
];

const SQL_KEY = new RegExp(
  `'(${Object.keys(PERMISSION_STRINGS).map(escapeRegExp).join("|")})'`,
  "g",
);

/**
 * Renames the permission keys in the app's own SQL (`can(...,
 * 'parties.read')`).
 */
function renameSqlKeys(source: string): CodemodResult {
  const text = source.replaceAll(
    SQL_KEY,
    (_match, key: string) => `'${renamed(PERMISSION_STRINGS, key)}'`,
  );

  const review = source
    .split("\n")
    .flatMap((line, index) =>
      REVIEW_0_46.filter((hint) => hint.pattern.test(line)).map((hint) => ({
        line: index + 1,
        message: hint.message,
      })),
    );

  return { text, review };
}

/** The oauth-server block's names, which now write `Oauth` like `create<Name>`. */
const OAUTH_SERVER_IMPORTS: Readonly<
  Record<string, Readonly<Record<string, string>>>
> = {
  "blocks/oauth-server": {
    createOAuthServer: "createOauthServer",
    OAuthServer: "OauthServer",
    OAuthServerOptions: "OauthServerOptions",
    OAuthServerEvents: "OauthServerEvents",
    OAuthClient: "OauthClient",
    OAuthClientAuthMethod: "OauthClientAuthMethod",
    OAuthClientMetadata: "OauthClientMetadata",
    OAuthClientEventData: "OauthClientEventData",
    RegisteredOAuthClient: "RegisteredOauthClient",
    OAuthAuthorization: "OauthAuthorization",
    OAuthGrant: "OauthGrant",
    OAuthGrantType: "OauthGrantType",
    OAuthGrantEventData: "OauthGrantEventData",
  },
};

/**
 * `codemod 0.46`: the naming convention's permission keys (ADR 0130). PRs that
 * rename event types, hint codes and entity keys add their rewrites here.
 */
export const CODEMOD_0_46: Codemod = {
  name: RENAMES_CODEMOD,
  description:
    "Renames createOAuthServer and the oauth-server block's OAuth types to Oauth, renames permission keys to the block-name areas and the read, write and manage verbs (parties.read to contacts.read, rules.edit to automations.write, support.start to impersonation.start, ...) in config, code and the app's SQL, and lists the ai.* keys, the split workflow.* keys, the support.* and workflow.* wildcards, members.invite for the waitlist and organization.export for review",
  subpathImports: OAUTH_SERVER_IMPORTS,
  strings: PERMISSION_STRINGS,
  sqlFile: renameSqlKeys,
  review: REVIEW_0_46,
};
