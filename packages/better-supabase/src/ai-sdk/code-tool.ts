import type { Experimental_SandboxSession, Tool } from "ai";

import { jsonSchema, tool } from "ai";

export type CodeLanguage = "python" | "node" | "bash";

export interface CodeToolInput {
  readonly language: CodeLanguage;
  readonly code: string;
}

/** What the model sees. A non-zero exit code is a result, not a tool error. */
export interface CodeToolOutput {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
  /** `true` when stdout or stderr was cut at `maxOutputBytes`. */
  readonly truncated: boolean;
  /** `true` when the run hit `timeoutMs`; `exitCode` is 124 then. */
  readonly timedOut: boolean;
}

export interface CodeToolOptions {
  /**
   * The session to run in. Without it the tool uses the call's
   * `experimental_sandbox`, so pass a deny-all sandbox there.
   */
  readonly sandbox?: Experimental_SandboxSession;
  /** Languages the model may use. Default all three. */
  readonly languages?: readonly CodeLanguage[];
  /** Milliseconds one run may take. Default 60000. */
  readonly timeoutMs?: number;
  /** Bytes kept of stdout and of stderr each. Default 16384. */
  readonly maxOutputBytes?: number;
  /** Where the snippet is written in the sandbox. Default `/tmp`. */
  readonly directory?: string;
  readonly description?: string;
}

const LANGUAGES: readonly CodeLanguage[] = ["python", "node", "bash"];

const RUNNERS: { readonly [L in CodeLanguage]: readonly [string, string] } = {
  python: ["python3", "py"],
  node: ["node", "mjs"],
  bash: ["bash", "sh"],
};

const TIMED_OUT = 124;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function cut(text: string, max: number): { text: string; cut: boolean } {
  const bytes = encoder.encode(text);

  return bytes.byteLength <= max
    ? { text, cut: false }
    : { text: decoder.decode(bytes.subarray(0, max)), cut: true };
}

const reasonOf = (signal: AbortSignal): Error =>
  signal.reason instanceof Error
    ? signal.reason
    : new Error("The run was stopped.", { cause: signal.reason });

/** Settles with `work`, or rejects when `signal` aborts first. */
async function until<T>(work: PromiseLike<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) {
    throw reasonOf(signal);
  }

  let abort = (): void => {};

  const aborted = new Promise<never>((_, reject) => {
    abort = () => {
      reject(reasonOf(signal));
    };
  });

  signal.addEventListener("abort", abort, { once: true });

  try {
    return await Promise.race([work, aborted]);
  } finally {
    signal.removeEventListener("abort", abort);
  }
}

/**
 * A tool that runs a Python, Node or Bash snippet in a sandbox session and
 * returns its exit code and output. Give it a sandbox without network access
 * (`untrusted` from `better-supabase/vercel-sandbox`) unless the code needs
 * one. To ask the user before each run, set `toolApproval` on the model call,
 * such as `{ runCode: "user-approval" }`.
 */
export function codeTool(
  options: CodeToolOptions = {},
): Tool<CodeToolInput, CodeToolOutput> {
  const languages = options.languages ?? LANGUAGES;
  const timeoutMs = options.timeoutMs ?? 60_000;
  const maxOutputBytes = options.maxOutputBytes ?? 16_384;
  const directory = options.directory ?? "/tmp";

  return tool({
    description:
      options.description ??
      `Run a ${languages.join(", ")} snippet in an isolated sandbox and read its exit code, stdout and stderr. Print what you need to see.`,
    inputSchema: jsonSchema<CodeToolInput>({
      type: "object",
      properties: {
        language: { type: "string", enum: [...languages] },
        code: { type: "string" },
      },
      required: ["language", "code"],
      additionalProperties: false,
    }),
    execute: async (
      { language, code },
      { toolCallId, abortSignal, experimental_sandbox },
    ): Promise<CodeToolOutput> => {
      if (!languages.includes(language)) {
        throw new Error(`The ${language} language is not enabled.`);
      }

      const session = options.sandbox ?? experimental_sandbox;

      if (session === undefined) {
        throw new Error(
          "codeTool needs a sandbox: pass experimental_sandbox or the sandbox option.",
        );
      }

      const [command, extension] = RUNNERS[language];
      const path = `${directory}/snippet-${toolCallId.replaceAll(/[^\w-]/g, "_")}.${extension}`;
      const timeout = AbortSignal.timeout(timeoutMs);

      const signal =
        abortSignal === undefined
          ? timeout
          : AbortSignal.any([abortSignal, timeout]);

      try {
        await until(
          session.writeTextFile({ path, content: code, abortSignal: signal }),
          signal,
        );

        const result = await until(
          session.run({ command: `${command} ${path}`, abortSignal: signal }),
          signal,
        );

        const stdout = cut(result.stdout, maxOutputBytes);
        const stderr = cut(result.stderr, maxOutputBytes);

        return {
          exitCode: result.exitCode,
          stdout: stdout.text,
          stderr: stderr.text,
          truncated: stdout.cut || stderr.cut,
          timedOut: false,
        };
      } catch (cause) {
        if (timeout.aborted && abortSignal?.aborted !== true) {
          return {
            exitCode: TIMED_OUT,
            stdout: "",
            stderr: `Stopped after ${timeoutMs} ms.`,
            truncated: false,
            timedOut: true,
          };
        }

        throw cause;
      }
    },
  });
}
