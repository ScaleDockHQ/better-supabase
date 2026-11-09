import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";

import type { AdvisorSource, Lint } from "../../../src/cli/doctor/advisors.ts";
import type { ExecResult } from "../../../src/cli/exec.ts";

import {
  cliAdvisors,
  isLoopbackUrl,
  parseAdvisorOutput,
  versionAtLeast,
  withFallback,
} from "../../../src/cli/doctor/cli-advisors.ts";

const lint = (name: string): Lint => ({
  name,
  title: name,
  level: "WARN",
  facing: "EXTERNAL",
  categories: ["PERFORMANCE"],
  description: "",
  detail: "",
  remediation: "",
  metadata: null,
  cache_key: name,
});

const ok = (stdout: string): ExecResult => ({ code: 0, stdout, stderr: "" });
const LOCAL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

describe("versionAtLeast", () => {
  it("compares releases", () => {
    expect(versionAtLeast("2.81.3", "2.81.3")).toBe(true);
    expect(versionAtLeast("2.90.0", "2.81.3")).toBe(true);
    expect(versionAtLeast("2.81.2", "2.81.3")).toBe(false);
    expect(versionAtLeast("1.200.0", "2.81.3")).toBe(false);
  });
});

describe("isLoopbackUrl", () => {
  it("only accepts this machine", () => {
    expect(isLoopbackUrl(LOCAL)).toBe(true);
    expect(isLoopbackUrl("postgres://u:p@db.example.com:5432/postgres")).toBe(
      false,
    );
    expect(isLoopbackUrl("not a url")).toBe(false);
  });
});

describe("parseAdvisorOutput", () => {
  it("reads a list or an object with lints", () => {
    const one = JSON.stringify([lint("a")]);

    expect(parseAdvisorOutput(one)).toHaveLength(1);
    expect(
      parseAdvisorOutput(JSON.stringify({ lints: [lint("a")] })),
    ).toHaveLength(1);
    expect(() => parseAdvisorOutput("{}")).toThrow(/no lints/);
  });
});

describe("cliAdvisors", () => {
  it("returns undefined for a remote database or an old CLI", async () => {
    const run = vi.fn(() => Promise.resolve(ok("2.81.2")));

    expect(
      await cliAdvisors({ run, dbUrl: "postgres://h.example.com/db" }),
    ).toBeUndefined();
    expect(run).not.toHaveBeenCalled();
    expect(await cliAdvisors({ run, dbUrl: LOCAL })).toBeUndefined();
  });

  it("runs db advisors for each category", async () => {
    const run = vi.fn((args: readonly string[]) =>
      Promise.resolve(
        args[0] === "--version"
          ? ok("2.84.1\n")
          : ok(JSON.stringify([lint(args[args.indexOf("--type") + 1] ?? "")])),
      ),
    );

    const source = await cliAdvisors({ run, dbUrl: LOCAL });
    const lints = await source?.lints("security");

    expect(lints?.map((each) => each.name)).toEqual(["security"]);
    expect(run).toHaveBeenLastCalledWith(
      expect.arrayContaining([
        "db",
        "advisors",
        "--db-url",
        LOCAL,
        "-o",
        "json",
      ]),
    );
  });
});

describe("withFallback", () => {
  const splinter: AdvisorSource = {
    describe: "database (splinter)",
    lints: () => Promise.resolve([lint("splinter")]),
  };

  it("uses splinter when the CLI is missing", async () => {
    const source = withFallback(() => Promise.resolve(undefined), splinter);

    expect(
      (await source.lints("performance")).map((each) => each.name),
    ).toEqual(["splinter"]);
  });

  it("uses splinter when the CLI fails", async () => {
    const source = withFallback(
      () =>
        Promise.resolve({
          describe: "cli",
          lints: () => Promise.reject(new Error("exit 1")),
        }),
      splinter,
    );

    expect(
      (await source.lints("performance")).map((each) => each.name),
    ).toEqual(["splinter"]);
  });

  it("prefers the CLI when it works", async () => {
    const source = withFallback(
      () =>
        Promise.resolve({
          describe: "cli",
          lints: () => Promise.resolve([lint("cli")]),
        }),
      splinter,
    );

    expect(
      (await source.lints("performance")).map((each) => each.name),
    ).toEqual(["cli"]);
  });
});

describe("parseAdvisorOutput shape drift", () => {
  it("throws when no entry looks like a lint, so the caller falls back", () => {
    expect(() => parseAdvisorOutput('[{"rule":"x"}]')).toThrow(
      "unknown lint shape",
    );
  });
});

describe("a saved `supabase db advisors -o json` document", () => {
  const saved = readFileSync(
    new URL("fixtures/db-advisors.json", import.meta.url),
    "utf-8",
  );

  it("parses every lint with its level, category and metadata", () => {
    const lints = parseAdvisorOutput(saved);

    expect(lints.map((each) => `${each.level} ${each.name}`)).toEqual([
      "INFO unindexed_foreign_keys",
      "WARN auth_rls_initplan",
      "ERROR rls_disabled_in_public",
    ]);
    expect(lints[0]?.metadata).toMatchObject({ name: "notes" });
  });

  it("reads the same lints wrapped in an object or one per line", () => {
    const list: unknown = JSON.parse(saved);

    expect(parseAdvisorOutput(JSON.stringify({ lints: list }))).toHaveLength(3);

    const lines = (Array.isArray(list) ? list : [])
      .map((each: unknown) => JSON.stringify(each))
      .join("\n");

    expect(parseAdvisorOutput(lines)).toHaveLength(3);
  });

  it("passes the type and level flags the CLI documents", async () => {
    const run = vi.fn((args: readonly string[]) =>
      Promise.resolve(args[0] === "--version" ? ok("2.122.0") : ok(saved)),
    );

    const source = await cliAdvisors({ run, dbUrl: LOCAL });

    expect(await source?.lints("performance")).toHaveLength(3);
    expect(run).toHaveBeenLastCalledWith([
      "db",
      "advisors",
      "--db-url",
      LOCAL,
      "--type",
      "performance",
      "--level",
      "info",
      "-o",
      "json",
    ]);
  });

  it("falls back to splinter when a newer CLI prints another shape", async () => {
    const splinter: AdvisorSource = {
      describe: "splinter",
      lints: () => Promise.resolve([lint("splinter")]),
    };

    const source = withFallback(
      () =>
        cliAdvisors({
          run: (args) =>
            Promise.resolve(
              args[0] === "--version"
                ? ok("3.0.0")
                : ok('{"advisors":{"performance":[{"rule":"x"}]}}'),
            ),
          dbUrl: LOCAL,
        }),
      splinter,
    );

    expect(
      (await source.lints("performance")).map((each) => each.name),
    ).toEqual(["splinter"]);
  });
});
