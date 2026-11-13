import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { RunProcess } from "../../../src/cli/exec.ts";

import { gitIgnored, ignoredBy } from "../../../src/cli/doctor/git-ignored.ts";

describe("ignoredBy", () => {
  it("matches gitignore patterns the way git does for files", () => {
    expect(ignoredBy([".env*"], ".env.development.local")).toBe(true);
    expect(ignoredBy([".env*"], "apps/web/.env")).toBe(true);
    expect(ignoredBy(["/.env"], "apps/web/.env")).toBeUndefined();
    expect(ignoredBy(["apps/*/.env"], "apps/web/.env")).toBe(true);
    expect(ignoredBy(["apps/*/.env"], "apps/web/deep/.env")).toBeUndefined();
    expect(ignoredBy(["apps/**/.env"], "apps/web/deep/.env")).toBe(true);
    expect(ignoredBy(["secrets/"], "secrets/.env")).toBe(true);
    expect(ignoredBy(["# .env", ""], ".env")).toBeUndefined();
  });

  it("lets the last matching rule decide, so a negation keeps a file", () => {
    expect(ignoredBy([".env*", "!.env.example"], ".env.example")).toBe(false);
    expect(ignoredBy([".env*", "!.env.example"], ".env.local")).toBe(true);
  });
});

describe("gitIgnored", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-ignored-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const answering =
    (code: number, stdout = ""): RunProcess =>
    () =>
      Promise.resolve({ code, stdout, stderr: "" });

  it("asks git check-ignore in a work tree", async () => {
    const calls: (readonly string[])[] = [];

    const run: RunProcess = (_command, args) => {
      calls.push(args);

      return Promise.resolve({
        code: 0,
        stdout: ".env.development.local\n",
        stderr: "",
      });
    };

    const ignored = await gitIgnored(
      root,
      [".env", ".env.development.local"],
      {},
      run,
    );

    expect(calls).toEqual([
      ["check-ignore", "--", ".env", ".env.development.local"],
    ]);
    expect([...ignored]).toEqual([".env.development.local"]);
  });

  it("takes git's answer that nothing is ignored", async () => {
    await writeFile(join(root, ".gitignore"), ".env\n");

    expect([...(await gitIgnored(root, [".env"], {}, answering(1)))]).toEqual(
      [],
    );
  });

  // EX-1614: the app's .env file was ignored by the root .gitignore only.
  it("reads every .gitignore up to the repository root without git", async () => {
    const app = join(root, "apps/web");
    await mkdir(join(root, ".git"), { recursive: true });
    await mkdir(app, { recursive: true });
    await writeFile(join(root, ".gitignore"), ".env*\n!.env.example\n");
    await writeFile(join(app, ".gitignore"), "!.env.production\n");

    const ignored = await gitIgnored(
      app,
      [".env.development.local", ".env.example", ".env.production"],
      {},
      answering(128),
    );

    expect([...ignored]).toEqual([".env.development.local"]);
  });

  it("falls back to the files when git can't start", async () => {
    await mkdir(join(root, ".git"));
    await writeFile(join(root, ".gitignore"), "/.env\n");

    const run: RunProcess = () => Promise.reject(new Error("spawn git ENOENT"));

    expect([...(await gitIgnored(root, [".env"], {}, run))]).toEqual([".env"]);
  });
});
