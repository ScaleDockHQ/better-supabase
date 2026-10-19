/**
 * Agent mode: who runs the CLI, and what an agent gets back when a person
 * has to act. Detection reads only the environment `run()` is given and the
 * probe, never `process`, so tests and embedders stay pure. The signals
 * follow `@vercel/detect-agent`, which `tests/cli/core/agent.test.ts` checks.
 */

import { createHash } from "node:crypto";

import type { NextStep } from "./io.ts";

import { CliError } from "./errors.ts";
import { isSecretKey, redactUrl } from "./redact.ts";
import { commandLine } from "./shell.ts";

/** What detection can't read from the environment. */
export interface AgentProbe {
  /** Stdout is a terminal, so a person may be watching. */
  readonly stdoutIsTty: boolean;
  /** Whether a path exists on the host. */
  readonly exists: (path: string) => boolean;
}

/** `--agent` and `$BETTER_SUPABASE_AGENT`: detect (`auto`), or force agent mode on or off. */
export type AgentSetting = "auto" | "yes" | "no";

type Env = Readonly<Record<string, string | undefined>>;

const DEVIN_PATH = "/opt/.devin";

/** The name used when agent mode is forced on and nothing is detected. */
const UNKNOWN_AGENT = "agent";

const set = (value: string | undefined): boolean =>
  value !== undefined && value !== "";

/**
 * The coding agent running the CLI, or `undefined` for a person. Cursor sets
 * `CURSOR_TRACE_ID` in a person's terminal too, so it counts only when
 * stdout is not a terminal.
 */
export function detectAgent(env: Env, probe: AgentProbe): string | undefined {
  const named = env["AI_AGENT"]?.trim();

  if (named) {
    return named === "github-copilot-cli" ? "github-copilot" : named;
  }

  const signals: readonly (readonly [boolean, string])[] = [
    [set(env["CURSOR_TRACE_ID"]) && !probe.stdoutIsTty, "cursor"],
    [
      set(env["CURSOR_AGENT"]) ||
        env["CURSOR_EXTENSION_HOST_ROLE"] === "agent-exec",
      "cursor-cli",
    ],
    [set(env["GEMINI_CLI"]), "gemini"],
    [
      set(env["CODEX_SANDBOX"]) ||
        set(env["CODEX_CI"]) ||
        set(env["CODEX_THREAD_ID"]),
      "codex",
    ],
    [set(env["ANTIGRAVITY_AGENT"]), "antigravity"],
    [set(env["AUGMENT_AGENT"]), "augment-cli"],
    [set(env["OPENCODE_CLIENT"]), "opencode"],
    [
      (set(env["CLAUDECODE"]) || set(env["CLAUDE_CODE"])) &&
        set(env["CLAUDE_CODE_IS_COWORK"]),
      "cowork",
    ],
    [set(env["CLAUDECODE"]) || set(env["CLAUDE_CODE"]), "claude"],
    [set(env["REPL_ID"]), "replit"],
    [
      set(env["COPILOT_MODEL"]) ||
        set(env["COPILOT_ALLOW_ALL"]) ||
        set(env["COPILOT_GITHUB_TOKEN"]),
      "github-copilot",
    ],
  ];

  const found = signals.find(([matches]) => matches);

  if (found) {
    return found[1];
  }

  return probe.exists(DEVIN_PATH) ? "devin" : undefined;
}

const SETTINGS: Readonly<Record<string, AgentSetting>> = {
  auto: "auto",
  yes: "yes",
  true: "yes",
  "1": "yes",
  no: "no",
  false: "no",
  "0": "no",
};

function settingOf(value: string, source: string): AgentSetting {
  const setting = SETTINGS[value.trim().toLowerCase()];

  if (!setting) {
    throw new CliError(
      "usage",
      `${source} takes auto, yes or no, got "${value}".`,
      source.startsWith("--") ? { flag: source } : {},
    );
  }

  return setting;
}

/** The agent in agent mode, or `undefined`: `--agent`, then `$BETTER_SUPABASE_AGENT`, then detection. */
export function resolveAgent(
  flag: string | undefined,
  env: Env,
  probe: AgentProbe,
): string | undefined {
  const fromEnv = env["BETTER_SUPABASE_AGENT"];

  const setting =
    flag === undefined
      ? fromEnv === undefined || fromEnv === ""
        ? "auto"
        : settingOf(fromEnv, "$BETTER_SUPABASE_AGENT")
      : settingOf(flag, "--agent");

  switch (setting) {
    case "no": {
      return undefined;
    }

    case "yes": {
      return detectAgent(env, probe) ?? UNKNOWN_AGENT;
    }

    case "auto": {
      return detectAgent(env, probe);
    }

    default: {
      const unknown: never = setting;

      return unknown;
    }
  }
}

/** The bin `next` commands start with: the package name, since `npx bsb` fetches an unrelated package. */
const NEXT_BIN = "better-supabase";

/** `argv` without `--name value` and `--name=value`, before any `--`. */
function withoutOption(argv: readonly string[], name: string): string[] {
  const out: string[] = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index] ?? "";

    if (arg === "--") {
      out.push(...argv.slice(index));
      break;
    }

    if (arg === name) {
      index += 1;
    } else if (!arg.startsWith(`${name}=`)) {
      out.push(arg);
    }
  }

  return out;
}

/**
 * `argv` safe to print: a secret-looking flag becomes its `--*-stdin`
 * form, and a URL loses its password.
 */
function shareable(argv: readonly string[]): string[] {
  const out: string[] = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index] ?? "";
    const name = arg.startsWith("--") ? arg.slice(2).split("=")[0] : undefined;

    if (name !== undefined && !name.endsWith("-stdin") && isSecretKey(name)) {
      out.push(`--${name}-stdin`);

      if (!arg.includes("=")) {
        index += 1;
      }
    } else {
      out.push(/^[a-z][a-z\d+.-]*:\/\//i.test(arg) ? redactUrl(arg) : arg);
    }
  }

  return out;
}

/** `argv` as the command to run next, with `extra` before any `--`. */
export function nextCommand(
  argv: readonly string[],
  extra: readonly string[],
): string {
  const words = shareable(argv);
  const end = words.indexOf("--");

  return commandLine(
    end === -1
      ? [NEXT_BIN, ...words, ...extra]
      : [NEXT_BIN, ...words.slice(0, end), ...extra, ...words.slice(end)],
  );
}

/**
 * The step that answers an `input_required` error: the run again with the
 * first choice of each missing flag (or a placeholder) and `--yes`.
 */
export function missingInputNext(
  argv: readonly string[],
  missing: readonly string[],
  choices: Readonly<Record<string, readonly string[]>> = {},
): NextStep {
  const filled = missing.flatMap((flag) => [
    flag,
    choices[flag]?.[0] ?? `<${flag.replace(/^-+/, "")}>`,
  ]);

  const yes = argv.includes("--yes") || argv.includes("-y") ? [] : ["--yes"];

  return {
    command: nextCommand(argv, [...filled, ...yes]),
    when:
      missing.length === 1 && (choices[missing[0] ?? ""]?.length ?? 0) > 1
        ? `with the value the user picks from choices["${missing[0] ?? ""}"]`
        : "with the values the user gives",
  };
}

/** Destructive work that waits for a person's consent in agent mode. */
export interface ConsentRequest {
  /** A stable id for the kind of work: `overwrite`, `database-write`. */
  readonly effect: string;
  /** What happens, as a sentence the agent can show the user. */
  readonly detail: string;
}

/** The token for one request on one command line, so a consent covers only that run. */
export function consentToken(
  argv: readonly string[],
  request: ConsentRequest,
): string {
  return createHash("sha256")
    .update(
      JSON.stringify([
        request.effect,
        request.detail,
        withoutOption(argv, "--confirm"),
      ]),
    )
    .digest("hex")
    .slice(0, 16);
}

/**
 * Nothing when `confirm` is the request's token, else a `consent_required`
 * error with the token and the command to run once the user agrees.
 */
export function checkConsent(
  argv: readonly string[],
  request: ConsentRequest,
  confirm: string | undefined,
): void {
  const token = consentToken(argv, request);

  if (confirm === token) {
    return;
  }

  const stale =
    confirm === undefined
      ? ""
      : " The --confirm token is for another command or another target.";

  throw new CliError(
    "consent_required",
    `${request.detail}. Ask the user first, then run again with --confirm ${token}.${stale}`,
    {
      token,
      next: [
        {
          command: nextCommand(withoutOption(argv, "--confirm"), [
            "--confirm",
            token,
          ]),
          when: "after the user agrees",
        },
      ],
    },
  );
}

const LOCAL_HOSTS: ReadonlySet<string> = new Set([
  "localhost",
  "127.0.0.1",
  "::1",
  "[::1]",
  "0.0.0.0",
  "host.docker.internal",
]);

/** Whether a connection string points at this machine, like the local stack. */
export function isLocalDatabaseUrl(url: string): boolean {
  try {
    const { hostname } = new URL(url);

    return hostname === "" || LOCAL_HOSTS.has(hostname.toLowerCase());
  } catch {
    return false;
  }
}

/** The host a connection string points at, without credentials. */
export function databaseHost(url: string): string {
  try {
    const { host } = new URL(url);

    return host === "" ? "a local socket" : host;
  } catch {
    return "the database";
  }
}
