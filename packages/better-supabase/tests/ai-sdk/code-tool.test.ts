import type { Experimental_SandboxSession, ToolExecutionOptions } from "ai";

import { describe, expect, it } from "vitest";

import type { CodeToolInput, CodeToolOutput } from "../../src/ai-sdk/index.ts";

import { codeTool } from "../../src/ai-sdk/index.ts";

interface Recorded {
  session: Experimental_SandboxSession;
  writes: { path: string; content: string }[];
  commands: string[];
}

function fakeSession(
  run: (
    signal: AbortSignal | undefined,
  ) => Promise<{ exitCode: number; stdout: string; stderr: string }>,
): Recorded {
  const writes: Recorded["writes"] = [];
  const commands: string[] = [];

  const session = {
    description: "fake",
    writeTextFile: async (options: { path: string; content: string }) => {
      writes.push({ path: options.path, content: options.content });
    },
    run: (options: { command: string; abortSignal?: AbortSignal }) => {
      commands.push(options.command);

      return run(options.abortSignal);
    },
  };

  // SAFETY: codeTool only calls writeTextFile and run.
  return {
    session: session as unknown as Experimental_SandboxSession,
    writes,
    commands,
  };
}

const ok =
  (stdout = "", stderr = "", exitCode = 0) =>
  async () => ({ exitCode, stdout, stderr });

function call(
  tool: ReturnType<typeof codeTool>,
  input: CodeToolInput,
  options: Partial<ToolExecutionOptions<unknown>> = {},
): Promise<CodeToolOutput> {
  if (tool.execute === undefined) {
    throw new Error("codeTool has no execute");
  }

  // SAFETY: codeTool's execute returns a promise, never a stream.
  return tool.execute(input, {
    toolCallId: "call/1",
    messages: [],
    context: undefined,
    ...options,
  }) as Promise<CodeToolOutput>;
}

describe("codeTool", () => {
  it("writes the snippet and runs it with the language's runner", async () => {
    const fake = fakeSession(ok("2\n"));
    const tool = codeTool({ sandbox: fake.session });

    const output = await call(tool, { language: "python", code: "print(1+1)" });

    expect(output).toEqual({
      exitCode: 0,
      stdout: "2\n",
      stderr: "",
      truncated: false,
      timedOut: false,
    });
    expect(fake.writes).toEqual([
      { path: "/tmp/snippet-call_1.py", content: "print(1+1)" },
    ]);
    expect(fake.commands).toEqual(["python3 /tmp/snippet-call_1.py"]);
  });

  it("uses the call's experimental_sandbox when no sandbox is set", async () => {
    const fake = fakeSession(ok());

    await call(
      codeTool(),
      { language: "node", code: "1" },
      { experimental_sandbox: fake.session },
    );

    expect(fake.commands).toEqual(["node /tmp/snippet-call_1.mjs"]);
  });

  it("returns a failing exit code as data", async () => {
    const fake = fakeSession(ok("", "boom", 1));

    const output = await call(codeTool({ sandbox: fake.session }), {
      language: "bash",
      code: "exit 1",
    });

    expect(output).toMatchObject({ exitCode: 1, stderr: "boom" });
  });

  it("refuses a language outside the allow-list", async () => {
    const fake = fakeSession(ok());
    const tool = codeTool({ sandbox: fake.session, languages: ["python"] });

    await expect(call(tool, { language: "bash", code: "ls" })).rejects.toThrow(
      "bash language is not enabled",
    );
    expect(fake.commands).toEqual([]);
  });

  it("fails without a sandbox", async () => {
    await expect(
      call(codeTool(), { language: "python", code: "1" }),
    ).rejects.toThrow("needs a sandbox");
  });

  it("cuts long output at maxOutputBytes", async () => {
    const fake = fakeSession(ok("x".repeat(100), "y".repeat(5)));

    const output = await call(
      codeTool({ sandbox: fake.session, maxOutputBytes: 10 }),
      { language: "python", code: "1" },
    );

    expect(output).toMatchObject({
      stdout: "x".repeat(10),
      stderr: "yyyyy",
      truncated: true,
    });
  });

  it("stops a run at timeoutMs, even when the session ignores the signal", async () => {
    const fake = fakeSession(() => new Promise(() => {}));

    const output = await call(
      codeTool({ sandbox: fake.session, timeoutMs: 20 }),
      { language: "python", code: "while True: pass" },
    );

    expect(output).toMatchObject({ exitCode: 124, timedOut: true });
  });

  it("rethrows when the caller aborts", async () => {
    const controller = new AbortController();
    const fake = fakeSession(() => new Promise(() => {}));

    const running = call(
      codeTool({ sandbox: fake.session }),
      { language: "python", code: "1" },
      { abortSignal: controller.signal },
    );

    controller.abort(new Error("user stopped"));

    await expect(running).rejects.toThrow("user stopped");
  });

  it("restricts the input schema to the enabled languages", async () => {
    const tool = codeTool({ languages: ["python", "node"] });

    const schema: unknown = await Promise.resolve(
      // SAFETY: jsonSchema() keeps the JSON Schema on `jsonSchema`.
      (tool.inputSchema as { jsonSchema: unknown }).jsonSchema,
    );

    expect(schema).toMatchObject({
      properties: { language: { enum: ["python", "node"] } },
    });
  });
});
