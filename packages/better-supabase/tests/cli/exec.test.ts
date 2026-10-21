import { channel } from "node:diagnostics_channel";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { env as processEnv, execPath } from "node:process";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { EXEC_CHANNEL } from "../../src/cli/core/trace.ts";
import { parseEnv } from "../../src/cli/env.ts";
import { runProcess, spawnInherited, supabaseCli } from "../../src/cli/exec.ts";

const MISSING = "bsb-no-such-command-4f1c";

describe("runProcess", () => {
  let cwd: string;

  beforeEach(async () => {
    cwd = await mkdtemp(join(tmpdir(), "better-supabase-exec-"));
  });

  afterEach(async () => {
    await rm(cwd, { recursive: true, force: true });
  });

  it("captures the output and exit code with the process environment", async () => {
    const env = parseEnv({ ...processEnv, BSB_EXEC_PROBE: "seen" });

    const result = await runProcess(
      execPath,
      [
        "-e",
        "process.stdout.write(process.env.BSB_EXEC_PROBE); process.stderr.write('warn'); process.exit(3)",
      ],
      cwd,
      env,
    );

    expect(result).toEqual({ code: 3, stdout: "seen", stderr: "warn" });
  });

  it("publishes each run to the trace channel", async () => {
    const events: unknown[] = [];

    const listener = (event: unknown): void => {
      events.push(event);
    };

    channel(EXEC_CHANNEL).subscribe(listener);

    try {
      await runProcess(execPath, ["-e", ""], cwd, {});
    } finally {
      channel(EXEC_CHANNEL).unsubscribe(listener);
    }

    expect(events).toEqual([
      expect.objectContaining({ command: execPath, cwd, code: 0 }),
    ]);
  });

  it("returns 127 for a command that can't start", async () => {
    const result = await runProcess(MISSING, [], cwd, {});

    expect(result.code).toBe(127);
  });

  it("stops the command when the signal aborts", async () => {
    const controller = new AbortController();

    const running = runProcess(
      execPath,
      ["-e", "setTimeout(() => {}, 60_000)"],
      cwd,
      {},
      { signal: controller.signal },
    );

    controller.abort();

    expect((await running).code).not.toBe(0);
  });
});

describe("spawnInherited", () => {
  const options = { cwd: tmpdir(), env: processEnv };

  it("resolves to the exit code", async () => {
    expect(
      await spawnInherited(execPath, ["-e", "process.exit(4)"], options),
    ).toBe(4);
  });

  it("adds 128 to the signal that ended the command", async () => {
    expect(
      await spawnInherited(
        execPath,
        ["-e", "process.kill(process.pid, 'SIGTERM')"],
        options,
      ),
    ).toBe(143);
  });

  it("returns 127 for a command that can't start", async () => {
    expect(await spawnInherited(MISSING, [], options)).toBe(127);
  });
});

describe("supabaseCli", () => {
  it("fails with supabase_cli_missing when $SUPABASE_BIN can't start", async () => {
    await expect(
      supabaseCli(["--version"], tmpdir(), { SUPABASE_BIN: MISSING }),
    ).rejects.toMatchObject({ code: "supabase_cli_missing" });
  });

  it("returns the result of an aborted call instead of failing", async () => {
    const controller = new AbortController();
    controller.abort();

    const result = await supabaseCli(
      ["--version"],
      tmpdir(),
      { SUPABASE_BIN: MISSING },
      { signal: controller.signal },
    );

    expect(result.code).toBe(127);
  });
});
