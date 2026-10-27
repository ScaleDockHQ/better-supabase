/**
 * The 0.32 renames: tenant is the public word again (`auth.organization` and
 * `requireOrganization` from 0.15 go back to `auth.tenant` and
 * `requireTenant`), and the auth names follow supabase-js.
 */

import type { Codemod, CodemodConfigEdit, ReviewLine } from "./codemod.ts";

import { codeRanges } from "./code-ranges.ts";
import { isRecord } from "./guards.ts";
import { configObject, mask, properties } from "./sql/config-edit.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

const ENVIRONMENT_KEY = /^\$(?:development|production|test|ci)$/;

const lineAt = (source: string, index: number): number =>
  source.slice(0, index).split("\n").length;

function applyEdits(source: string, edits: readonly Edit[]): string {
  let text = source;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }

  return text;
}

/**
 * Renames `organization` to `tenant` in the `auth` object of the config at
 * `open`.
 */
function renameIn(
  source: string,
  code: string,
  open: number,
  review: ReviewLine[],
): Edit[] {
  const edits: Edit[] = [];

  for (const prop of properties(source, code, open) ?? []) {
    if (prop.key === undefined || code[prop.valueStart] !== "{") {
      continue;
    }

    if (prop.key === "auth") {
      const auth = properties(source, code, prop.valueStart) ?? [];
      const organization = auth.find((entry) => entry.key === "organization");

      if (organization === undefined) {
        continue;
      }

      if (auth.some((entry) => entry.key === "tenant")) {
        review.push({
          line: lineAt(source, organization.start),
          message:
            "`auth.organization` and `auth.tenant` are both set: move the `organization` entries into `tenant` by hand",
        });
        continue;
      }

      const keyStart = source.indexOf("organization", organization.start);
      edits.push({
        start: keyStart,
        end: keyStart + "organization".length,
        text: "tenant",
      });
    } else if (ENVIRONMENT_KEY.test(prop.key)) {
      edits.push(...renameIn(source, code, prop.valueStart, review));
    } else if (prop.key === "$env") {
      for (const environment of properties(source, code, prop.valueStart) ??
        []) {
        if (code[environment.valueStart] === "{") {
          edits.push(...renameIn(source, code, environment.valueStart, review));
        }
      }
    }
  }

  return edits;
}

function renameJson(value: unknown, review: ReviewLine[]): unknown {
  if (!isRecord(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, entry]) => {
      if (key === "auth" && isRecord(entry) && "organization" in entry) {
        if ("tenant" in entry) {
          review.push({
            line: 1,
            message:
              "`auth.organization` and `auth.tenant` are both set: move the `organization` entries into `tenant` by hand",
          });

          return [key, entry];
        }

        return [
          key,
          Object.fromEntries(
            Object.entries(entry).map(([name, item]) => [
              name === "organization" ? "tenant" : name,
              item,
            ]),
          ),
        ];
      }

      if (ENVIRONMENT_KEY.test(key)) {
        return [key, renameJson(entry, review)];
      }

      if (key === "$env" && isRecord(entry)) {
        return [
          key,
          Object.fromEntries(
            Object.entries(entry).map(([name, block]) => [
              name,
              renameJson(block, review),
            ]),
          ),
        ];
      }

      return [key, entry];
    }),
  );
}

/**
 * `better-supabase.config.*` with `auth.organization` renamed to `auth.tenant`,
 * at the top level and in the `$env` and `$<environment>` blocks.
 */
function organizationToTenant(
  source: string,
  json: boolean,
): CodemodConfigEdit {
  const review: ReviewLine[] = [];

  if (json) {
    let parsed: unknown;

    try {
      parsed = JSON.parse(source);
    } catch {
      return { ok: false, reason: "the file is not valid JSON" };
    }

    const renamed = renameJson(parsed, review);

    return JSON.stringify(renamed) === JSON.stringify(parsed)
      ? { ok: true, text: source, review }
      : { ok: true, text: `${JSON.stringify(renamed, null, 2)}\n`, review };
  }

  const code = mask(source);
  const open = configObject(code);

  if (open === undefined) {
    return /\borganization\s*:/.test(code)
      ? {
          ok: false,
          reason:
            "no defineConfig({...}) or exported object literal; rename `auth.organization` to `auth.tenant` by hand",
        }
      : { ok: true, text: source, review };
  }

  return {
    ok: true,
    text: applyEdits(source, renameIn(source, code, open, review)),
    review,
  };
}

const KEY_RENAMES: Readonly<Record<string, string>> = {
  requireOrganization: "requireTenant",
  checkSession: "verifySession",
  endedSession: "verifySession",
  refreshSkewSeconds: "leeway",
  expiredPrefetch: "onExpiredPrefetch",
};

/**
 * Option keys renamed in code, outside strings and comments: the route and
 * procedure `requireOrganization`, and the proxy and session-check options.
 */
function renameKeys(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const ranges = codeRanges(text);
  const names = Object.keys(KEY_RENAMES).join("|");
  const pattern = new RegExp(`(?<![\\w$])(?:${names})(?=\\s*[:,}])`, "g");

  const edits = [...text.matchAll(pattern)]
    .filter((match) =>
      ranges.some(([start, end]) => match.index >= start && match.index < end),
    )
    .map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: KEY_RENAMES[match[0]]!,
    }));

  return { text: applyEdits(text, edits), review: [] };
}

export const CODEMOD_0_32: Codemod = {
  name: "0.32",
  description:
    "Renames auth.organization to auth.tenant in better-supabase.config.* (at the top level and in the $env and $<environment> blocks), the requireOrganization route and procedure option to requireTenant, the createNext session, sign-in and cache methods to the supabase-js names (getClaims, contextFromSession, evictSession, signInWithOAuth, exchangeCodeForSession, tag, tags), the proxy and session-check option keys (verifySession, leeway, onExpiredPrefetch), checkSession to verifySession, and the matching types",
  imports: {
    OrganizationConfig: "TenantConfig",
    OAuthStart: "SignInWithOAuthParams",
    CodeExchange: "ExchangeCodeParams",
    EndedSessionOptions: "VerifySessionOptions",
    checkSession: "verifySession",
  },
  members: [
    { from: "getRequestSession", to: "getClaims" },
    { from: "contextForSession", to: "contextFromSession" },
    { from: "invalidateSession", to: "evictSession" },
    { from: "forgetSession", to: "evictSession" },
    { from: "authorizeUrl", to: "signInWithOAuth" },
    { from: "exchangeCode", to: "exchangeCodeForSession" },
    { from: "cacheTags", to: "tags" },
    { from: "cacheTag", to: "tag" },
  ],
  review: [
    {
      pattern: /\.session\(\)/,
      message:
        "`bsb.session()` is `bsb.claims()` now; the returned `AuthSession` is unchanged apart from `profile`, which is `userMetadata`",
    },
    {
      pattern: /\.signIn\(/,
      message:
        "`bsb.signIn()` is gone: call `bsb.signInWithPassword()` (the same arguments). The React hook and `oauth.signIn` keep their names",
    },
    {
      pattern:
        /\bkind\s*[!=]==?\s*["'](?:anon|service)["']|case\s+["'](?:anon|service)["']|\bkind:\s*["'](?:anon|service)["']/,
      message:
        "The caller kinds `anon` and `service` are `none` and `secret` now (`ctx.auth.kind`, `AuthSession.kind`). An actor (`ctx.actor.kind`) and a subscriber keep `anon` and `service`",
    },
    {
      pattern: /\ballow\s*:\s*\[[^\]]*["'](?:anon|service)["']/,
      message:
        "`allow` takes `none` (no session) and `secret` (the secret key) instead of `anon` and `service`",
    },
    {
      pattern: /\b(?:session|auth)\.profile\b/,
      message:
        "`AuthState.profile` and `AuthSession.profile` (the parsed `user_metadata`) are `userMetadata` now",
    },
    {
      pattern: /\bsessionEnded(?:Reason)?\b/,
      message:
        "The resolution carries `sessionVerified: false` and `reason` (`session_not_found` or `user_banned`) instead of `sessionEnded` and `sessionEndedReason` (`ended` or `banned`)",
    },
    {
      pattern:
        /onExpiredPrefetch\s*:\s*["']protect["']|expiredPrefetch\s*:\s*["']protect["']/,
      message:
        "`onExpiredPrefetch` takes `redirect` (the default) instead of `protect`",
    },
    {
      pattern: /\b(?:session_ended|account_banned)\b/,
      message:
        "The `verifySession` redirect sends `reason=session_not_found` or `reason=user_banned` (Auth's error codes) instead of `session_ended` and `account_banned`",
    },
    {
      pattern: /\bevictSession\(/,
      message:
        "`bsb.evictSession()` returns a promise now (it also evicts the session memo and version cache): await it",
    },
  ],
  configFile: organizationToTenant,
  source: renameKeys,
};
