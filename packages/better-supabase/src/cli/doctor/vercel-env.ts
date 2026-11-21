import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { ENV_VARIABLES, projectRefOf } from "../../env/index.ts";
import { envEntries, PUBLIC_PREFIXES } from "./env.ts";

/** The environments `vercel pull --environment=<name>` writes a file for. */
export const VERCEL_ENVIRONMENTS = [
  "development",
  "preview",
  "production",
] as const;

/** One environment's pulled variables, from `.vercel/.env.<name>.local`. */
export interface VercelEnvFile {
  readonly environment: string;
  readonly file: TextFile;
}

/** The path `vercel pull --environment=<name>` writes. */
export const vercelEnvPath = (environment: string): string =>
  `.vercel/.env.${environment}.local`;

/** The Supabase and database names of a project; the CLI's own are not. */
const RELEVANT =
  /(?:^|_)(?:SUPABASE_(?!ACCESS_TOKEN$|BIN$|API_URL$)[A-Z0-9_]+|POSTGRES_URL(?:_NON_POOLING)?|DATABASE_URL)$/;

/** A name that holds a secret once the public prefix is taken off. */
const SECRET_NAME =
  /SECRET|SERVICE_ROLE|JWT|PASSWORD|DB_URL|DATABASE_URL|POSTGRES_URL|PRIVATE/;

const LEGACY_PUBLISHABLE = /(?:^|_)SUPABASE_ANON_KEY$/;

/**
 * Names the library no longer reads; reported on their own, not per
 * environment.
 */
const LEGACY_KEY = /(?:^|_)SUPABASE_(?:ANON_KEY|SERVICE_ROLE_KEY)$/;

const names = (file: TextFile): Set<string> =>
  new Set(envEntries(file).map((entry) => entry.key));

const NO_FILES =
  "No pulled environment found. Run `vercel pull --environment=<name>` for production, preview and development first; doctor reads `.vercel/.env.<name>.local`.";

function missingNames(files: readonly VercelEnvFile[]): FindingInput[] {
  const sources = files.filter(
    (entry) =>
      entry.environment === "production" || entry.environment === "preview",
  );

  const expected = new Set(
    sources.flatMap((entry) =>
      [...names(entry.file)].filter(
        (name) => RELEVANT.test(name) && !LEGACY_KEY.test(name),
      ),
    ),
  );

  return files.flatMap((entry) => {
    const present = names(entry.file);
    const findings: FindingInput[] = [];

    const hasUrl = ENV_VARIABLES.url.some((name) => present.has(name));

    const hasKey =
      ENV_VARIABLES.publishableKey.some((name) => present.has(name)) ||
      present.has("SUPABASE_PUBLISHABLE_KEYS");

    const legacy = [...present].find((name) => LEGACY_PUBLISHABLE.test(name));

    if (!hasUrl) {
      findings.push({
        message: `${entry.environment} sets no SUPABASE_URL (plain or with a browser prefix), so the app finds no project there. Connect the Supabase integration to ${entry.environment}, or add the variable.`,
        target: `${entry.environment}:SUPABASE_URL`,
        location: { file: entry.file.path, line: 1 },
      });
    }

    if (!hasKey) {
      findings.push({
        message:
          legacy === undefined
            ? `${entry.environment} sets no SUPABASE_PUBLISHABLE_KEY (plain or with a browser prefix). Add it from Project Settings > API Keys.`
            : `${entry.environment} sets ${legacy}, the legacy name, but no SUPABASE_PUBLISHABLE_KEY. The library reads only the sb_publishable_ name. Add SUPABASE_PUBLISHABLE_KEY (and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY for the browser) and remove the legacy name.`,
        target: `${entry.environment}:SUPABASE_PUBLISHABLE_KEY`,
        location: { file: entry.file.path, line: 1 },
      });
    }

    for (const name of [...expected].toSorted()) {
      const others = sources
        .filter((source) => names(source.file).has(name))
        .map((source) => source.environment);

      if (
        !present.has(name) &&
        !(name === "SUPABASE_URL" && !hasUrl) &&
        !others.includes(entry.environment)
      ) {
        findings.push({
          message: `${name} is set for ${others.join(" and ")} but not for ${entry.environment}. A deployment there reads nothing. Connect the integration to ${entry.environment}, or add the variable.`,
          target: `${entry.environment}:${name}`,
          location: { file: entry.file.path, line: 1 },
        });
      }
    }

    return findings;
  });
}

const urlOf = (file: TextFile): string | undefined => {
  const entries = envEntries(file);

  for (const name of ENV_VARIABLES.url) {
    const value = entries.find((entry) => entry.key === name)?.value;

    if (value !== undefined && value !== "") {
      return value;
    }
  }

  return undefined;
};

/** The project a URL names: its ref, else its origin. */
function projectOf(url: string): string | undefined {
  const ref = projectRefOf(url);

  if (ref !== undefined) {
    return ref;
  }

  try {
    return new URL(url).origin;
  } catch {
    return undefined;
  }
}

/**
 * Checks on the variables `vercel pull` writes per environment (BS513 to
 * BS515), read with `doctor --vercel`. A value Vercel does not return (a
 * sensitive variable) is empty, so a name counts as set when the file lists
 * it.
 */
export const VERCEL_ENV_RULES: readonly Rule[] = [
  {
    code: "BS513",
    severity: "warning",
    title: "Vercel environment lacks a Supabase variable",
    description:
      "An environment of the Vercel project has no Supabase URL or publishable key, sets only the legacy SUPABASE_ANON_KEY name, or lacks a Supabase or database variable that production or preview sets. A deployment there fails at startup or talks to nothing. Checked by name, so a variable whose value Vercel hides still counts.",
    check: (context: DoctorContext) => {
      const files = context.vercelEnv;

      if (files === undefined) {
        return [];
      }

      return files.length === 0
        ? [{ message: NO_FILES, target: ".vercel" }]
        : missingNames(files);
    },
  },
  {
    code: "BS514",
    severity: "error",
    title: "Secret under a browser prefix in a Vercel environment",
    description:
      "A Vercel environment variable with a browser prefix (NEXT_PUBLIC_, VITE_, PUBLIC_, EXPO_PUBLIC_, NUXT_PUBLIC_) has a secret name (a secret or service role key, a JWT secret, a database URL or a password) or an sb_secret_ value. Vercel inlines it into client code at build time. Checked by name where the value is hidden.",
    check: (context: DoctorContext) =>
      (context.vercelEnv ?? []).flatMap((entry) =>
        envEntries(entry.file).flatMap((variable) => {
          const prefix = PUBLIC_PREFIXES.find((candidate) =>
            variable.key.startsWith(candidate),
          );

          if (
            prefix === undefined ||
            !(
              SECRET_NAME.test(variable.key.slice(prefix.length)) ||
              variable.value.startsWith("sb_secret_")
            )
          ) {
            return [];
          }

          return [
            {
              message: `${variable.key} is exposed to the browser in ${entry.environment} but holds a secret. Rename it without the public prefix, redeploy and rotate the key.`,
              target: `${entry.environment}:${variable.key}`,
              location: { file: entry.file.path, line: variable.line },
            },
          ];
        }),
      ),
  },
  {
    code: "BS515",
    severity: "warning",
    title: "Preview and production share a Supabase project",
    description:
      "The preview and production environments of the Vercel project point at one Supabase project (the same project ref, or the same URL when it is not a hosted ref). Every preview deployment then reads and writes production data. Give preview its own project or a branch database. Skipped when Vercel hides either URL.",
    check: (context: DoctorContext) => {
      const files = context.vercelEnv ?? [];
      const preview = files.find((entry) => entry.environment === "preview");

      const production = files.find(
        (entry) => entry.environment === "production",
      );

      if (preview === undefined || production === undefined) {
        return [];
      }

      const previewUrl = urlOf(preview.file);
      const productionUrl = urlOf(production.file);

      if (previewUrl === undefined || productionUrl === undefined) {
        return [];
      }

      const project = projectOf(previewUrl);

      return project !== undefined && project === projectOf(productionUrl)
        ? [
            {
              message:
                "Preview and production use the same Supabase project, so a preview deployment reads and writes production data. Connect preview to its own project or a branch database.",
              target: "preview:SUPABASE_URL",
              location: { file: preview.file.path, line: 1 },
            },
          ]
        : [];
    },
  },
];

/** The codes `--vercel` asks for even when `--only` leaves them out. */
export const VERCEL_CODES: readonly string[] = VERCEL_ENV_RULES.map(
  (rule) => rule.code,
);
