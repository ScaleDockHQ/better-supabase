import type { CliEnv } from "../env.ts";
import type { Rule, TextFile } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import { PROCESS_ENV } from "../env.ts";
import {
  PREFIX_NAMES,
  redactValue,
  stackEnvValues,
  staleVariables,
} from "../stack-env.ts";
import { readStackStatus } from "../stack-status.ts";

const PUBLIC_PREFIXES = [
  "NEXT_PUBLIC_",
  "VITE_",
  "PUBLIC_",
  "EXPO_PUBLIC_",
  "NUXT_PUBLIC_",
];

/** `SUPABASE_URL`, plain or with a browser prefix. */
const URL_VARIABLE = new RegExp(
  `^(?:${PUBLIC_PREFIXES.join("|")})?SUPABASE_URL$`,
);

/** The URL without a trailing slash, `null` for a value that isn't one. */
function normalizedUrl(value: string): string | null {
  try {
    return new URL(value).href.replace(/\/+$/, "");
  } catch {
    return null;
  }
}

function envEntries(
  file: TextFile,
): { key: string; value: string; line: number }[] {
  return file.text.split("\n").flatMap((raw, index) => {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(
      raw,
    );

    if (!match) {
      return [];
    }

    const value = match[2]!.trim().replace(/^(['"])(.*)\1$/, "$2");

    return [{ key: match[1]!, value, line: index + 1 }];
  });
}

/** The shell's variables next to the running stack's, for BS503. */
export type StackEnvCheck =
  | {
      readonly shell: Readonly<Record<string, string | undefined>>;
      readonly values: Readonly<Record<string, string>>;
    }
  | { readonly skipped: string };

const PREFIXES = [
  ...new Set(Object.values(PREFIX_NAMES).filter((prefix) => prefix !== "")),
];

/**
 * The names `stackEnvValues` writes, with or without a browser prefix; not the
 * CLI's own `SUPABASE_BIN` or `SUPABASE_ACCESS_TOKEN`.
 */
const STACK_VARIABLE =
  /(?:^|_)SUPABASE_(?:URL|PUBLISHABLE_KEY|SECRET_KEY|JWKS_URL|DB_URL|JWT_SECRET)$/;

const exportsStackVariable = (
  shell: Readonly<Record<string, string | undefined>>,
): boolean =>
  Object.entries(shell).some(
    ([name, value]) =>
      value !== undefined && value !== "" && STACK_VARIABLE.test(name),
  );

/**
 * Reads the running stack only when the shell exports a `SUPABASE_*` variable,
 * so a doctor run without one never starts `supabase status`.
 */
export async function loadStackEnvCheck(
  root: string,
  env: CliEnv,
  signal?: AbortSignal,
): Promise<StackEnvCheck> {
  const shell = env[PROCESS_ENV] ?? {};

  if (!exportsStackVariable(shell)) {
    return { skipped: "No SUPABASE_* variable is exported." };
  }

  try {
    const result = await readStackStatus(root, env, { signal });

    if (!result.ok) {
      return { skipped: "The local stack is not running." };
    }

    const values = { ...stackEnvValues(result.status, "") };

    if (values["SUPABASE_URL"] === undefined) {
      return { skipped: "supabase status has no API_URL." };
    }

    for (const prefix of PREFIXES) {
      values[`${prefix}SUPABASE_URL`] = values["SUPABASE_URL"];

      if (values["SUPABASE_PUBLISHABLE_KEY"] !== undefined) {
        values[`${prefix}SUPABASE_PUBLISHABLE_KEY`] =
          values["SUPABASE_PUBLISHABLE_KEY"];
      }
    }

    return { shell, values };
  } catch (cause) {
    return { skipped: errorText(cause) };
  }
}

/**
 * Checks on env files and the variables the shell exports (BS501 to BS503 and
 * BS506).
 */
export const ENV_RULES: readonly Rule[] = [
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

        if (!secret || ignored(file.path) || file.path.endsWith(".example")) {
          return [];
        }

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
  {
    code: "BS503",
    severity: "warning",
    title: "Exported Supabase variable differs from the running stack",
    description:
      "A SUPABASE_* variable exported in the shell has another value than the local stack, so the app talks to a stale stack (often another worktree's port). Values are redacted: host and port for URLs, a SHA-256 fingerprint for keys. Unset the variable, or start the app with `better-supabase dev run -- <cmd>`, which overrides it.",
    check: ({ stackEnv }) =>
      stackEnv === undefined || "skipped" in stackEnv
        ? []
        : staleVariables(stackEnv.shell, stackEnv.values).map((stale) => ({
            target: stale.variable,
            message: `${stale.message} Unset it or start the app with better-supabase dev run -- <cmd>.`,
          })),
  },
  {
    code: "BS506",
    severity: "warning",
    title: "Server and browser Supabase URLs differ",
    description:
      "The session cookie name comes from the project URL. When SUPABASE_URL and a browser-prefixed spelling such as NEXT_PUBLIC_SUPABASE_URL point at different URLs, the server and the browser client read different cookies, and a sign-in on one side is invisible to the other. Use one URL, or set auth.cookie.name on both clients when the split is intended (a custom domain in the browser, the project URL on the server).",
    check: (context) =>
      context.envFiles.flatMap((file) => {
        const urls = envEntries(file).filter(
          (entry) => URL_VARIABLE.test(entry.key) && entry.value !== "",
        );

        const [server] = urls;

        if (!server) {
          return [];
        }

        const expected = normalizedUrl(server.value);

        return urls
          .filter(
            (entry) =>
              expected !== null &&
              normalizedUrl(entry.value) !== null &&
              normalizedUrl(entry.value) !== expected,
          )
          .map((entry) => ({
            message: `${entry.key} in ${file.path} (${redactValue(entry.value)}) differs from ${server.key} (${redactValue(server.value)}). The server and the browser then read different session cookies. Use one URL, or set auth.cookie.name on both clients.`,
            target: `${file.path}:${entry.key}`,
            location: { file: file.path, line: entry.line },
          }));
      }),
  },
];
