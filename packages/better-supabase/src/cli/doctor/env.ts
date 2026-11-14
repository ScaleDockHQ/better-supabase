import type { CliEnv } from "../env.ts";
import type { Rule, TextFile } from "./rules.ts";

import { ENV_VARIABLES, parseEnv } from "../../env/index.ts";
import { errorText } from "../core/errors.ts";
import { PROCESS_ENV } from "../env.ts";
import {
  PREFIX_NAMES,
  redactValue,
  stackEnvValues,
  staleVariables,
} from "../stack-env.ts";
import { readStackStatus } from "../stack-status.ts";
import { ignoredBy } from "./git-ignored.ts";

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
      /**
       * The `kid` of every key the stack's JWKS URL serves; `undefined` when
       * the shell exports no `SUPABASE_JWKS` or the endpoint can't be read.
       */
      readonly stackKeyIds?: readonly string[];
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
  /(?:^|_)SUPABASE_(?:URL|PUBLISHABLE_KEY|SECRET_KEY|JWKS(?:_URL)?|DB_URL|JWT_SECRET)$/;

const exportsStackVariable = (
  shell: Readonly<Record<string, string | undefined>>,
): boolean =>
  Object.entries(shell).some(
    ([name, value]) =>
      value !== undefined && value !== "" && STACK_VARIABLE.test(name),
  );

const JWKS_TIMEOUT_MS = 5000;

/** The `kid` of each key in a JWKS document (`{"keys":[...]}` or `[...]`). */
function keyIds(document: unknown): string[] | undefined {
  const keys =
    typeof document === "object" && document !== null && "keys" in document
      ? document.keys
      : document;

  if (!Array.isArray(keys) || keys.length === 0) {
    return undefined;
  }

  const ids = keys.map((key: unknown) =>
    typeof key === "object" &&
    key !== null &&
    "kid" in key &&
    typeof key.kid === "string"
      ? key.kid
      : undefined,
  );

  return ids.every((id) => id !== undefined) ? ids : undefined;
}

/** The key ids the stack serves, or `undefined` when it can't be read. */
async function fetchStackKeyIds(
  url: string,
  signal?: AbortSignal,
): Promise<string[] | undefined> {
  try {
    const response = await fetch(url, {
      signal: AbortSignal.any([
        AbortSignal.timeout(JWKS_TIMEOUT_MS),
        ...(signal ? [signal] : []),
      ]),
    });

    return response.ok ? keyIds(await response.json()) : undefined;
  } catch {
    return undefined;
  }
}

function inlineKeyIds(value: string): string[] | undefined {
  try {
    return keyIds(JSON.parse(value));
  } catch {
    return undefined;
  }
}

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

    const inline = shell["SUPABASE_JWKS"];
    const jwksUrl = values["SUPABASE_JWKS_URL"];

    const stackKeyIds =
      inline && jwksUrl ? await fetchStackKeyIds(jwksUrl, signal) : undefined;

    return stackKeyIds ? { shell, values, stackKeyIds } : { shell, values };
  } catch (cause) {
    return { skipped: errorText(cause) };
  }
}

/**
 * Checks on env files and the variables the shell exports (BS501 to BS503,
 * BS506 and BS509).
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
      const lines = context.gitignore.split("\n");

      const ignored = (path: string): boolean =>
        context.ignoredEnvFiles?.has(path) ?? ignoredBy(lines, path) === true;

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
            message: `${file.path} contains ${secret.key} but git doesn't ignore it. Add it to a .gitignore, or untrack it with \`git rm --cached\` if it was committed.`,
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
    check: ({ stackEnv }) => {
      if (stackEnv === undefined || "skipped" in stackEnv) {
        return [];
      }

      const stale = staleVariables(stackEnv.shell, stackEnv.values).map(
        (entry) => ({
          target: entry.variable,
          message: `${entry.message} Unset it or start the app with better-supabase dev run -- <cmd>.`,
        }),
      );

      // SUPABASE_JWKS wins over SUPABASE_JWKS_URL, so inline keys from a
      // hosted project reject every token the local stack signs. `env:local`
      // writes the stack's own public keys there, which is fine.
      const inlineKeys = stackEnv.shell["SUPABASE_JWKS"];

      const inlineIds =
        inlineKeys === undefined ? undefined : inlineKeyIds(inlineKeys);

      const servedByStack =
        inlineIds !== undefined &&
        stackEnv.stackKeyIds !== undefined &&
        inlineIds.every((id) => stackEnv.stackKeyIds?.includes(id));

      return inlineKeys === undefined || inlineKeys === "" || servedByStack
        ? stale
        : [
            ...stale,
            {
              target: "SUPABASE_JWKS",
              message:
                "SUPABASE_JWKS is exported, so tokens verify against those keys instead of the running stack's SUPABASE_JWKS_URL. Unset it while you work against the local stack.",
            },
          ];
    },
  },
  {
    code: "BS509",
    severity: "error",
    title: "SUPABASE_JWKS does not parse",
    description:
      "SUPABASE_JWKS holds the project's signing keys inline, so the server verifies tokens without fetching the JWKS URL. loadEnv rejects a value that is not JSON or holds no key with a kty, and the server then fails to start. Fill it with the output of `curl <url>/auth/v1/.well-known/jwks.json`.",
    check: (context) =>
      context.envFiles.flatMap((file) =>
        envEntries(file)
          .filter(
            (entry) => entry.key === "SUPABASE_JWKS" && entry.value !== "",
          )
          .flatMap((entry) => {
            const result = parseEnv({ SUPABASE_JWKS: entry.value });

            const issue = result.ok
              ? undefined
              : result.issues.find(
                  (found) => found.variables === ENV_VARIABLES.jwks,
                );

            return issue === undefined
              ? []
              : [
                  {
                    message: `SUPABASE_JWKS in ${file.path} ${issue.message}. Fill it with the output of curl <url>/auth/v1/.well-known/jwks.json, or leave it empty to fetch SUPABASE_JWKS_URL.`,
                    target: `${file.path}:${entry.key}`,
                    location: { file: file.path, line: entry.line },
                  },
                ];
          }),
      ),
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
