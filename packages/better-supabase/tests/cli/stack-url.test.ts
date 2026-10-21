import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { databaseUrl } from "../../src/cli/config.ts";
import { readStackStatus } from "../../src/cli/stack-status.ts";
import { resolveConfig } from "../../src/config/index.ts";

vi.mock(import("../../src/cli/stack-status.ts"), () => ({
  readStackStatus: vi.fn(),
}));

const status = vi.mocked(readStackStatus);

describe("databaseUrl with a named stack", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-stack-"));
    await mkdir(join(root, "supabase/stacks/tests"), { recursive: true });
    await writeFile(join(root, "supabase/config.toml"), "[db]\nport = 54322\n");

    await writeFile(
      join(root, "supabase/stacks/tests/config.toml"),
      "[db]\nport = 54422\n",
    );
  });

  afterEach(async () => {
    status.mockReset();
    await rm(root, { recursive: true, force: true });
  });

  it("reads the port of that stack", async () => {
    const config = resolveConfig({}, root);

    expect(await databaseUrl(config, {}, undefined, "tests")).toBe(
      "postgresql://postgres:postgres@127.0.0.1:54422/postgres",
    );
  });

  it("reads $BSB_STACK when no stack is passed", async () => {
    const config = resolveConfig({}, root);

    expect(await databaseUrl(config, { BSB_STACK: "tests" })).toContain(
      ":54422/",
    );
  });

  it("rejects an unknown or unsafe stack", async () => {
    const config = resolveConfig({}, root);
    status.mockResolvedValue({ ok: false, code: 1 });

    await expect(databaseUrl(config, {}, undefined, "demo")).rejects.toThrow(
      "supabase/stacks/demo/config.toml sets no [db] port",
    );

    await expect(databaseUrl(config, {}, undefined, "../x")).rejects.toThrow(
      "must be lowercase",
    );
  });

  it("keeps a connection string over a stack", async () => {
    const config = resolveConfig({}, root);

    expect(
      await databaseUrl(
        config,
        { DATABASE_URL: "postgresql://u@h/d" },
        undefined,
        "tests",
      ),
    ).toBe("postgresql://u@h/d");
  });

  it("asks that stack's status when its config names no port", async () => {
    await writeFile(join(root, "supabase/stacks/tests/config.toml"), "");

    status.mockResolvedValue({
      ok: true,
      status: {
        DB_URL: "postgresql://postgres:postgres@127.0.0.1:61234/postgres",
      },
    });

    const config = resolveConfig({}, root);

    expect(await databaseUrl(config, {}, undefined, "tests")).toContain(
      ":61234/",
    );

    expect(status).toHaveBeenCalledWith(root, {}, { stack: "tests" });
  });

  it("fails naming both sources when that stack's status fails", async () => {
    await writeFile(join(root, "supabase/stacks/tests/config.toml"), "");
    status.mockResolvedValue({ ok: false, code: 1 });

    const config = resolveConfig({}, root);

    await expect(
      databaseUrl(config, {}, undefined, "tests"),
    ).rejects.toMatchObject({
      code: "not_found",
      message: expect.stringMatching(
        /stacks\/tests\/config\.toml sets no \[db\] port, and `supabase status --stack tests` failed \(exit 1\)/,
      ),
    });
  });
});

describe("databaseUrl with the default stack", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-stack-"));
    await mkdir(join(root, "supabase"), { recursive: true });
    await writeFile(join(root, "supabase/config.toml"), 'project_id = "x"\n');
  });

  afterEach(async () => {
    status.mockReset();
    await rm(root, { recursive: true, force: true });
  });

  it("uses the running stack's DB_URL when config.toml names no port", async () => {
    status.mockResolvedValue({
      ok: true,
      status: {
        DB_URL: "postgresql://postgres:postgres@127.0.0.1:55432/postgres",
      },
    });

    expect(await databaseUrl(resolveConfig({}, root), {})).toContain(":55432/");
  });

  it("fails instead of guessing 54322 when supabase status fails", async () => {
    status.mockResolvedValue({ ok: false, code: 1 });

    await expect(
      databaseUrl(resolveConfig({}, root), {}),
    ).rejects.toMatchObject({
      code: "not_found",
      message: expect.stringMatching(
        /supabase\/config\.toml sets no \[db\] port, and `supabase status` failed \(exit 1\)/,
      ),
    });
  });

  it("fails when supabase status throws", async () => {
    status.mockRejectedValue(new Error("boom"));

    await expect(databaseUrl(resolveConfig({}, root), {})).rejects.toThrow(
      "boom",
    );
  });
});
