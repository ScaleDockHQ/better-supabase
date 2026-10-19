import { determineAgent } from "@vercel/detect-agent";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  type AgentProbe,
  checkConsent,
  consentToken,
  databaseHost,
  detectAgent,
  isLocalDatabaseUrl,
  missingInputNext,
  nextCommand,
  resolveAgent,
} from "../../../src/cli/core/agent.ts";
import { defineCliCommand } from "../../../src/cli/core/command.ts";
import { CliError } from "../../../src/cli/core/errors.ts";
import { createCli } from "../../../src/cli/core/run.ts";

const PIPE: AgentProbe = { stdoutIsTty: false, exists: () => false };
const TERMINAL: AgentProbe = { stdoutIsTty: true, exists: () => false };

/** Every variable either detector reads. */
const SIGNALS = [
  "AI_AGENT",
  "CURSOR_TRACE_ID",
  "CURSOR_AGENT",
  "CURSOR_EXTENSION_HOST_ROLE",
  "GEMINI_CLI",
  "CODEX_SANDBOX",
  "CODEX_CI",
  "CODEX_THREAD_ID",
  "ANTIGRAVITY_AGENT",
  "AUGMENT_AGENT",
  "OPENCODE_CLIENT",
  "CLAUDECODE",
  "CLAUDE_CODE",
  "CLAUDE_CODE_IS_COWORK",
  "REPL_ID",
  "COPILOT_MODEL",
  "COPILOT_ALLOW_ALL",
  "COPILOT_GITHUB_TOKEN",
] as const;

const SCENARIOS: readonly Readonly<Record<string, string>>[] = [
  { AI_AGENT: "my-agent" },
  { AI_AGENT: "github-copilot-cli" },
  { CURSOR_TRACE_ID: "trace" },
  { CURSOR_AGENT: "1" },
  { CURSOR_EXTENSION_HOST_ROLE: "agent-exec" },
  { GEMINI_CLI: "1" },
  { CODEX_SANDBOX: "seatbelt" },
  { CODEX_CI: "1" },
  { CODEX_THREAD_ID: "thread" },
  { ANTIGRAVITY_AGENT: "1" },
  { AUGMENT_AGENT: "1" },
  { OPENCODE_CLIENT: "1" },
  { CLAUDECODE: "1" },
  { CLAUDE_CODE: "1" },
  { CLAUDECODE: "1", CLAUDE_CODE_IS_COWORK: "1" },
  { REPL_ID: "repl" },
  { COPILOT_MODEL: "gpt" },
  { COPILOT_ALLOW_ALL: "1" },
  { COPILOT_GITHUB_TOKEN: "token" },
  { CURSOR_TRACE_ID: "trace", CLAUDECODE: "1" },
  { AI_AGENT: "named", CLAUDECODE: "1" },
];

describe("detectAgent", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it.each(SCENARIOS)(
    "names the same agent as @vercel/detect-agent for %o",
    async (scenario) => {
      for (const name of SIGNALS) {
        vi.stubEnv(name, scenario[name]);
      }

      const vercel = await determineAgent();

      expect(detectAgent(scenario, PIPE)).toBe(
        vercel.isAgent ? vercel.agent.name : undefined,
      );
    },
  );

  it("ignores CURSOR_TRACE_ID when stdout is a terminal", () => {
    expect(detectAgent({ CURSOR_TRACE_ID: "trace" }, TERMINAL)).toBeUndefined();
  });

  it("detects Devin from its marker file, and nothing in a plain shell", () => {
    expect(
      detectAgent(
        {},
        { stdoutIsTty: true, exists: (path) => path === "/opt/.devin" },
      ),
    ).toBe("devin");
    expect(detectAgent({}, TERMINAL)).toBeUndefined();
  });
});

describe("resolveAgent", () => {
  it("takes --agent, then $BETTER_SUPABASE_AGENT, then detection", () => {
    const env = { CLAUDECODE: "1", BETTER_SUPABASE_AGENT: "no" };

    expect(resolveAgent(undefined, env, PIPE)).toBeUndefined();
    expect(resolveAgent("auto", env, PIPE)).toBe("claude");
    expect(resolveAgent(undefined, { CLAUDECODE: "1" }, PIPE)).toBe("claude");
    expect(resolveAgent("yes", {}, PIPE)).toBe("agent");
    expect(resolveAgent(undefined, { BETTER_SUPABASE_AGENT: "1" }, PIPE)).toBe(
      "agent",
    );
  });

  it("rejects other values as a usage error", () => {
    expect(() => resolveAgent("maybe", {}, PIPE)).toThrow(
      '--agent takes auto, yes or no, got "maybe".',
    );
    expect(() =>
      resolveAgent(undefined, { BETTER_SUPABASE_AGENT: "sure" }, PIPE),
    ).toThrow(CliError);
  });
});

describe("next commands", () => {
  it("swaps secrets for their stdin flags and redacts URLs", () => {
    expect(
      nextCommand(
        [
          "gen",
          "--access-token",
          "sbp_secret",
          "--db",
          "postgresql://u:pw@db.example.com/x",
        ],
        ["--yes"],
      ),
    ).toBe(
      "better-supabase gen --access-token-stdin --db postgresql://u:redacted@db.example.com/x --yes",
    );
  });

  it("puts the extra flags before --", () => {
    expect(nextCommand(["exec", "--", "vitest"], ["--yes"])).toBe(
      "better-supabase exec --yes -- vitest",
    );
  });

  it("fills the first choice for a missing flag and adds --yes once", () => {
    expect(
      missingInputNext(["init"], ["--package"], {
        "--package": ["apps/web", "."],
      }),
    ).toEqual({
      command: "better-supabase init --package apps/web --yes",
      when: 'with the value the user picks from choices["--package"]',
    });
    expect(missingInputNext(["init", "--yes"], ["--name"]).command).toBe(
      "better-supabase init --yes --name '<name>'",
    );
  });
});

describe("consent", () => {
  const request = {
    effect: "overwrite",
    detail: "init --force overwrites files",
  };

  it("passes with the token for the same command, ignoring --confirm itself", () => {
    const token = consentToken(["init", "--force"], request);

    expect(token).toMatch(/^[\da-f]{16}$/);
    expect(consentToken(["init", "--force", "--confirm", token], request)).toBe(
      token,
    );
    expect(() => {
      checkConsent(["init", "--force", "--confirm", token], request, token);
    }).not.toThrow();
  });

  it("asks for consent with the token and the command to run after it", () => {
    const token = consentToken(["init", "--force"], request);

    expect(() => {
      checkConsent(["init", "--force"], request, undefined);
    }).toThrow(
      expect.objectContaining({
        code: "consent_required",
        exitCode: 3,
        problem: expect.objectContaining({ token }),
        next: [
          {
            command: `better-supabase init --force --confirm ${token}`,
            when: "after the user agrees",
          },
        ],
      }),
    );
  });

  it("rejects a token for another command", () => {
    const other = consentToken(
      ["init", "--force", "--cwd", "elsewhere"],
      request,
    );

    expect(() => {
      checkConsent(["init", "--force"], request, other);
    }).toThrow(/for another command or another target/);
  });

  it("treats only this machine as a local database", () => {
    expect(
      isLocalDatabaseUrl("postgresql://postgres@127.0.0.1:54322/postgres"),
    ).toBe(true);
    expect(isLocalDatabaseUrl("postgresql://postgres@localhost/postgres")).toBe(
      true,
    );
    expect(isLocalDatabaseUrl("postgresql://postgres@[::1]/postgres")).toBe(
      true,
    );
    expect(
      isLocalDatabaseUrl("postgresql://u:pw@db.abc.supabase.co/postgres"),
    ).toBe(false);
    expect(isLocalDatabaseUrl("not a url")).toBe(false);
    expect(
      databaseHost("postgresql://u:pw@db.abc.supabase.co:5432/postgres"),
    ).toBe("db.abc.supabase.co:5432");
  });
});

describe("agent mode in run()", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-agent-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const cli = createCli({
    commands: {
      mode: defineCliCommand({
        meta: { name: "mode" },
        args: { force: { type: "boolean" }, "dry-run": { type: "boolean" } },
        run: (_args, { agent, json, io }) =>
          Promise.resolve({
            code: 0,
            output: "text",
            data: {
              agent: agent ?? null,
              json,
              prompts: io.prompts !== undefined,
            },
          }),
      }),
      ask: defineCliCommand({
        meta: { name: "ask" },
        args: {},
        run: () =>
          Promise.reject(
            new CliError("input_required", "Pick a package.", {
              missing: ["--package"],
              choices: { "--package": ["apps/web", "."] },
            }),
          ),
      }),
    },
  });

  const prompts = {
    select: () => Promise.resolve(undefined),
    multiselect: () => Promise.resolve(undefined),
    confirm: () => Promise.resolve(false),
  };

  const io = { stdout: () => {}, stderr: () => {}, prompts };

  it("prints JSON without prompts when an agent runs it", async () => {
    const result = await cli.run(["mode", "--cwd", dir], {
      env: { CLAUDECODE: "1" },
      io,
    });

    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      status: "success",
      data: { agent: "claude", json: true, prompts: false },
    });
  });

  it("prints text with --no-json and runs as a person with --agent no", async () => {
    const text = await cli.run(["mode", "--no-json", "--cwd", dir], {
      env: { CLAUDECODE: "1" },
      io,
    });

    expect(text.stdout).toBe("text\n");

    const person = await cli.run(["mode", "--agent", "no", "--cwd", dir], {
      env: { CLAUDECODE: "1" },
      io,
    });

    expect(person.stdout).toBe("text\n");
  });

  it("keeps --help and --version as text in agent mode", async () => {
    const version = await cli.run(["--version"], { env: { CLAUDECODE: "1" } });
    expect(version.stdout).toMatch(/^\d+\.\d+\.\d+/);

    const help = await cli.run(["mode", "--help"], {
      env: { CLAUDECODE: "1" },
    });

    expect(help.stdout).not.toMatch(/^\{/);
  });

  it("rejects a bad --agent value as a usage error", async () => {
    const result = await cli.run(["mode", "--agent", "maybe", "--cwd", dir]);

    expect(result.code).toBe(2);
    expect(result.stderr).toContain(
      '--agent takes auto, yes or no, got "maybe".',
    );
  });

  it("points the old skills install --agent at --for instead of agent mode", async () => {
    const result = await cli.run(
      ["skills", "install", "--agent", "cursor", "--json", "--cwd", dir],
      { env: {} },
    );

    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      error: { code: "flag_renamed" },
    });
  });

  it("answers a missing input with action_required and the next command", async () => {
    const result = await cli.run(["ask", "--cwd", dir], {
      env: { CLAUDECODE: "1" },
    });

    expect(result.code).toBe(3);
    expect(JSON.parse(result.stdout)).toMatchObject({
      status: "action_required",
      error: {
        code: "input_required",
        missing: ["--package"],
        choices: { "--package": ["apps/web", "."] },
      },
      next: [
        {
          command: `better-supabase ask --cwd ${dir} --package apps/web --yes`,
        },
      ],
    });
  });

  it("asks for consent before --force overwrites, and runs with the token", async () => {
    const argv = ["mode", "--force", "--cwd", dir];
    const first = await cli.run(argv, { env: { CLAUDECODE: "1" } });

    expect(first.code).toBe(3);

    const body = JSON.parse(first.stdout) as {
      readonly status: string;
      readonly error: { readonly code: string; readonly token: string };
    };

    expect(body.status).toBe("action_required");
    expect(body.error.code).toBe("consent_required");

    const agreed = await cli.run([...argv, "--confirm", body.error.token], {
      env: { CLAUDECODE: "1" },
    });

    expect(agreed.code).toBe(0);

    const yes = await cli.run([...argv, "--yes"], { env: { CLAUDECODE: "1" } });
    expect(yes.code).toBe(3);

    const person = await cli.run(argv, { env: {} });
    expect(person.code).toBe(0);
  });

  it("asks no consent for --force under --dry-run", async () => {
    const result = await cli.run(
      ["mode", "--force", "--dry-run", "--cwd", dir],
      {
        env: { CLAUDECODE: "1" },
      },
    );

    expect(result.code).toBe(0);
  });
});
