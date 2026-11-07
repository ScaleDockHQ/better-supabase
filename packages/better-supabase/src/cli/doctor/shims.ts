import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { lineOf } from "./shared.ts";

/**
 * One piece of app code the library replaced. A shim matches when its pattern
 * is in a source file that also names the library, so a project that never
 * imports better-supabase is left alone.
 */
export interface Shim {
  readonly code: string;
  readonly title: string;
  /** What the app wrote, in the finding's words. */
  readonly found: string;
  /** What replaces it. */
  readonly replacement: string;
  /** The version that shipped the replacement. */
  readonly since: string;
  readonly pattern: RegExp;
  /** An extra condition on the file's text, for shims that need two signals. */
  readonly also?: RegExp;
}

const LIBRARY = /better-supabase|lib\/supabase/;

/**
 * The shims doctor reports (BS612 to BS619). Add an entry to report another
 * one; the rules, the schema enum and the docs list read from this table.
 */
export const SHIMS: readonly Shim[] = [
  {
    code: "BS612",
    title: "Proxy re-syncs session cookies with setAll",
    found: "a `setAll` cookie callback in a proxy or middleware file",
    replacement: "the library's own cookie handling in `bsb.proxy`",
    since: "0.40",
    pattern: /\bsetAll\s*[:(]/,
    also: /\b(?:proxy|middleware)\b/i,
  },
  {
    code: "BS613",
    title: "An extra Auth call follows bootstrap",
    found: "`auth.getUser()` or `auth.getClaims()` next to `bootstrap`",
    replacement:
      "`Bootstrap.endReason`, which says why a session ended without a second Auth call",
    since: "0.44",
    pattern: /\bauth\.(?:getUser|getClaims)\s*\(/,
    also: /\bbootstrap\s*\(/,
  },
  {
    code: "BS614",
    title: "The authorization version is seeded by hand after bootstrap",
    found: "a manual authorization version seed",
    replacement: "the seed `bootstrap` already makes from the live version",
    since: "0.44",
    pattern: /\b(?:seedAuthzVersion|seedAuthorizerVersion|seedVersion)\s*\(/,
    also: /\bbootstrap\b/,
  },
  {
    code: "BS615",
    title: "Comment paging filters deletedAt in the app",
    found: "a `deletedAt` filter on a comment list",
    replacement: "`includeDeleted` on the comments client",
    since: "0.47",
    pattern: /\.filter\([^\n]*deletedAt/,
    also: /\bcomments?\b/i,
  },
  {
    code: "BS616",
    title: "Comment authors are read again after a comment list",
    found: "a `hydrateStoredComments` helper or a profile read after a list",
    replacement:
      "`Message.author` (`{ id, name, avatarUrl }`), which comments return when `profiles` is installed",
    since: "0.47",
    pattern:
      /\bhydrateStoredComments\b|\bcomments?\b[\s\S]{0,300}\bfrom\(\s*["']profiles["']\s*\)[\s\S]{0,200}\.in\(\s*["']id["']/,
  },
  {
    code: "BS617",
    title: "Policy roles are mapped by hand",
    found: "`withPublicPolicyRoles`",
    replacement:
      "the catalog query, which maps empty policy roles to public itself",
    since: "0.45",
    pattern: /\bwithPublicPolicyRoles\b/,
  },
  {
    code: "BS618",
    title: "A unique violation is detected by code or message",
    found: '`code === "23505"` or a message search for a constraint name',
    replacement: "`isConflict(error, constraint)`",
    since: "0.47",
    pattern:
      /\bcode\s*===?\s*["']23505["']|\b(?:message|details)\b[^;\n]*\.(?:includes|match)\(\s*["'][\w]*(?:_key|_idx|unique)[\w]*["']/,
  },
  {
    code: "BS619",
    title: "A support caller is built as an AuthState by hand",
    found: 'an object literal with `source: "cookie"`',
    replacement:
      "`SupportCaller` (`{ token, claims }`), which the support API turns into an `AuthState`",
    since: "0.47",
    pattern: /\bsource\s*:\s*["']cookie["']/,
    also: /\bsupport\b/i,
  },
  {
    code: "BS620",
    title: "Settings are merged into one JSON blob by hand",
    found:
      "an `update({ settings: { ...old, ... } })` merge on a settings column",
    replacement:
      "the `settings` block, which validates each key against a Standard Schema and writes one key at a time",
    since: "0.54",
    pattern: /\.update\(\s*\{\s*settings\s*:\s*\{\s*\.\.\./,
  },
];

function lineOfMatch(file: TextFile, pattern: RegExp): number {
  return lineOf(file.text, new RegExp(pattern.source)) ?? 1;
}

function matches(file: TextFile, shim: Shim): boolean {
  return (
    LIBRARY.test(file.text) &&
    shim.pattern.test(file.text) &&
    (shim.also?.test(file.text) ?? true)
  );
}

/** Findings for one shim, one per source file that still carries it. */
export function shimFindings(
  context: Pick<DoctorContext, "sources">,
  shim: Shim,
): FindingInput[] {
  return context.sources
    .filter((file) => matches(file, shim))
    .map((file) => ({
      message: `${file.path} has ${shim.found}. Since ${shim.since}, use ${shim.replacement}.`,
      target: file.path,
      location: { file: file.path, line: lineOfMatch(file, shim.pattern) },
    }));
}

export const SHIM_RULES: readonly Rule[] = SHIMS.map((shim) => ({
  code: shim.code,
  severity: "info",
  title: shim.title,
  description: `The app carries ${shim.found}. Since ${shim.since} the library covers it: use ${shim.replacement}. The check reads source text matched by \`doctor.sources\`.`,
  check: (context: DoctorContext) => shimFindings(context, shim),
}));
