import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { PROCESS_ENV, parseEnv } from "../../src/cli/env.ts";
import {
  parseStackStatus,
  readStackStatus,
} from "../../src/cli/stack-status.ts";

describe("parseStackStatus", () => {
  it("reads the object after the progress lines", () => {
    expect(
      parseStackStatus('Starting...\n{"API_URL":"http://127.0.0.1:1"}'),
    ).toEqual({ API_URL: "http://127.0.0.1:1" });
  });

  it("returns nothing without a JSON object", () => {
    expect(parseStackStatus("Stopped")).toBeUndefined();
    expect(parseStackStatus("null")).toBeUndefined();
  });
});

describe("readStackStatus", () => {
  let root = "";

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-stack-status-"));
  });

  afterEach(() => rm(root, { recursive: true, force: true }));

  async function fakeSupabase(script: string): Promise<string> {
    const bin = join(root, "fake-supabase");
    await writeFile(bin, `#!/bin/sh\n${script}\n`);
    await chmod(bin, 0o755);

    return bin;
  }

  it("returns the exit code when both status forms fail", async () => {
    const bin = await fakeSupabase("exit 3");
    expect(await readStackStatus(root, { SUPABASE_BIN: bin })).toEqual({
      ok: false,
      code: 3,
    });
  });

  it("runs the project's node_modules/.bin/supabase with the run's environment", async () => {
    await mkdir(join(root, "node_modules", ".bin"), { recursive: true });
    const bin = join(root, "node_modules", ".bin", "supabase");
    await writeFile(bin, '#!/bin/sh\nprintf \'{"FROM":"%s"}\' "$BS_MARKER"\n');
    await chmod(bin, 0o755);

    const env = parseEnv({ ...process.env, BS_MARKER: "local" });
    expect(env[PROCESS_ENV]?.["BS_MARKER"]).toBe("local");
    expect(await readStackStatus(root, env)).toEqual({
      ok: true,
      status: { FROM: "local" },
    });
  });

  it("fails with supabase_cli_missing instead of downloading one", async () => {
    await expect(
      readStackStatus(root, { SUPABASE_BIN: join(root, "missing") }),
    ).rejects.toMatchObject({ code: "supabase_cli_missing" });
  });

  it("rejects a status that prints no JSON", async () => {
    const bin = await fakeSupabase("echo Stopped");
    await expect(readStackStatus(root, { SUPABASE_BIN: bin })).rejects.toThrow(
      "supabase status printed no JSON.",
    );
  });
});
