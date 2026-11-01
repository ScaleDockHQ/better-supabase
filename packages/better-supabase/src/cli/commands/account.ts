import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { Fetch } from "../seeds/cloud.ts";

import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import {
  billingSummary,
  clearLogin,
  CloudError,
  DEFAULT_CLOUD_URL,
  isExpired,
  pollLogin,
  readLogin,
  saveLogin,
  startLogin,
  tokenPath,
} from "../seeds/cloud.ts";

/** The cloud app the account commands call. */
export const cloudUrl = (env: CliEnv): string =>
  (env.BSB_CLOUD_URL ?? DEFAULT_CLOUD_URL).replace(/\/$/, "");

export interface LoginTools {
  readonly fetch: Fetch;
  readonly sleep: (ms: number) => Promise<void>;
  readonly now: () => number;
  readonly show: (text: string) => void;
}

const REAL_TOOLS: LoginTools = {
  fetch: (input, init) => fetch(input, init),
  sleep: (ms) =>
    new Promise((done) => {
      setTimeout(done, ms);
    }),
  now: () => Date.now(),
  show: () => {},
};

/** The device flow: show the URL, then poll until approved or expired. */
export async function runLogin(
  env: CliEnv,
  tools: LoginTools = REAL_TOOLS,
): Promise<CommandResult> {
  const base = cloudUrl(env);

  try {
    const start = await startLogin(tools.fetch, base);

    tools.show(
      `Open ${start.verificationUrl} and confirm the code ${start.userCode}.`,
    );

    const deadline = tools.now() + start.expiresIn * 1000;

    while (tools.now() < deadline) {
      await tools.sleep(Math.max(1, start.interval) * 1000);

      try {
        const grant = await pollLogin(tools.fetch, base, start.deviceCode);
        const stored = await saveLogin(tokenPath(env), grant);

        return {
          code: 0,
          output: `Logged in as ${stored.email}.`,
          data: { email: stored.email, expiresAt: stored.expiresAt },
        };
      } catch (error) {
        if (!(error instanceof CloudError && error.kind === "pending")) {
          throw error;
        }
      }
    }

    return {
      code: 1,
      errorCode: "request_failed",
      error:
        "The login was not approved in time. Run `better-supabase login` again.",
    };
  } catch (error) {
    return cloudFailure(error);
  }
}

/** The result for a cloud failure, with the next step when the user can act. */
export function cloudFailure(error: unknown): CommandResult {
  if (!(error instanceof CloudError)) {
    throw error;
  }

  switch (error.kind) {
    case "network": {
      return { code: 1, errorCode: "network_error", error: error.message };
    }

    case "unauthorized": {
      return {
        code: 3,
        errorCode: "auth_required",
        error: "You are not logged in, or the login expired.",
        next: [{ command: "better-supabase login", when: "to log in again" }],
      };
    }

    case "upgrade": {
      return {
        code: 3,
        errorCode: "auth_required",
        error: `${error.message}. Upgrade at ${error.upgrade ?? "https://app.bettersupabase.com/billing"}.`,
        data: { upgrade: error.upgrade },
        next: [
          {
            command: `open ${error.upgrade ?? "https://app.bettersupabase.com/billing"}`,
            when: "to upgrade to a plan with sample data",
          },
        ],
      };
    }

    case "pending":
    case "expired":
    case "rejected": {
      return { code: 1, errorCode: "request_failed", error: error.message };
    }

    default: {
      const never: never = error.kind;

      throw new Error(`Unhandled cloud error ${String(never)}`);
    }
  }
}

export async function runLogout(env: CliEnv): Promise<CommandResult> {
  const existed = await clearLogin(tokenPath(env));

  return {
    code: 0,
    output: existed ? "Logged out." : "You were not logged in.",
    data: { loggedIn: false },
  };
}

export async function runWhoami(
  env: CliEnv,
  fetcher: Fetch = REAL_TOOLS.fetch,
  now: number = Date.now(),
): Promise<CommandResult> {
  const login = await readLogin(tokenPath(env));

  if (login === undefined || isExpired(login, now)) {
    return cloudFailure(
      new CloudError("unauthorized", "Not logged in", { status: 401 }),
    );
  }

  try {
    const billing = await billingSummary(
      fetcher,
      cloudUrl(env),
      login.accessToken,
    );

    return {
      code: 0,
      output: `${login.email} (${billing.plan} plan)`,
      data: { email: login.email, plan: billing.plan },
    };
  } catch (error) {
    return cloudFailure(error);
  }
}

export const loginCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("login"),
  args: {},
  run: (_args, { env, log }) =>
    runLogin(env, {
      ...REAL_TOOLS,
      show: (text) => {
        log.info(text);
      },
    }),
});

export const logoutCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("logout"),
  args: {},
  run: (_args, { env }) => runLogout(env),
});

export const whoamiCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("whoami"),
  args: {},
  run: (_args, { env, log }) =>
    log.progress("Reading the account", () => runWhoami(env)),
});
