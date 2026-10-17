import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { fileState, staleResult, writeLine } from "../../src/cli/files.ts";
import { readIfExists } from "../../src/cli/io.ts";

describe("cli files", () => {
  it("compares a missing, equal and different file", async () => {
    const root = await mkdtemp(join(tmpdir(), "files-"));
    expect((await fileState(root, "a.txt", "x\n")).upToDate).toBe(false);
    await writeFile(join(root, "a.txt"), "x\r\n");
    const state = await fileState(root, "a.txt", "x\n");
    expect(state.upToDate).toBe(true);
    expect(staleResult(state, "cmd")).toEqual({
      code: 0,
      output: "a.txt is up to date.",
    });
    const stale = staleResult(await fileState(root, "a.txt", "y\n"), "cmd");
    expect(stale).toMatchObject({
      code: 1,
      error: "a.txt is out of date. Run `cmd`.",
    });
    expect(stale.output?.split("\n")).toEqual([
      "--- a.txt\ton disk",
      "+++ a.txt\tgenerated",
      "@@ -1,1 +1,1 @@",
      "-x\r",
      "+y",
    ]);

    const missing = staleResult(
      await fileState(root, "none.txt", "z\n"),
      "cmd",
    );

    expect(missing.output).toContain("--- none.txt\tmissing");
    expect(missing.output).toContain("+z");
  });

  it("writes once, then reports Unchanged", async () => {
    const root = await mkdtemp(join(tmpdir(), "files-"));
    const path = join(root, "sub", "b.txt");
    expect(await writeLine(path, "hi", "sub/b.txt", " (1)")).toEqual({
      wrote: true,
      line: "Wrote sub/b.txt (1)",
    });
    expect((await writeLine(path, "hi", "sub/b.txt")).line).toBe(
      "Unchanged sub/b.txt",
    );
    expect(await readFile(path, "utf-8")).toBe("hi");
    expect(await readIfExists(join(root, "none"))).toBeUndefined();
  });
});
