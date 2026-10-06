import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { CliIo } from "../../../src/cli/io.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  EXTRAS_RULES,
  skippedForMetadata,
} from "../../../src/cli/doctor/metadata.ts";
import { RULE_CODES } from "../../../src/cli/doctor/rules.ts";
import { fromMetadata } from "../../../src/cli/introspect/from-metadata.ts";
import { serializeGenerator } from "../../../src/cli/introspect/typegen.ts";
import { run } from "../../../src/cli/run.ts";
import { snapshotFixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(snapshotFixture);
const document = await serializeGenerator(snapshot.generator);

interface Report {
  findings: { code: string; severity: string; message: string }[];
}

describe("doctor --metadata", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-doctor-metadata-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const doctor = async (args: readonly string[], stdin: string = document) => {
    const stdout: string[] = [];
    const stderr: string[] = [];
    const io: CliIo = {
      stdout: (text) => {
        stdout.push(text);
      },
      stderr: (text) => {
        stderr.push(text);
      },
      stdin: () => Promise.resolve(stdin),
    };
    const result = await run(["doctor", ...args, "--cwd", root], { io });
    return { ...result, stdout: stdout.join(""), stderr: stderr.join("") };
  };

  it("only lists rules doctor has", () => {
    expect(
      [...EXTRAS_RULES].filter((code) => !RULE_CODES.includes(code)),
    ).toEqual([]);
  });

  it("skips the rules that need extras with an info finding, and runs the rest", async () => {
    const result = await doctor(["--metadata", "-", "--json"]);
    const report = JSON.parse(result.stdout) as Report;
    const skipped = report.findings.filter((finding) =>
      finding.message.startsWith(
        "Skipped: the schema came from a GeneratorMetadata document",
      ),
    );
    expect(skipped.map((finding) => finding.code).sort()).toEqual(
      [...EXTRAS_RULES].sort(),
    );
    expect(skipped.every((finding) => finding.severity === "info")).toBe(true);
    expect(
      report.findings.some(
        (finding) =>
          finding.code === "BS100" &&
          finding.message.includes("reading a GeneratorMetadata document"),
      ),
    ).toBe(true);
    expect(
      report.findings.filter(
        (finding) =>
          EXTRAS_RULES.has(finding.code) && finding.severity !== "info",
      ),
    ).toEqual([]);
  });

  it("exits 65 for a rejected document and refuses live flags", async () => {
    const rejected = await doctor(["--metadata", "-"], "{}");
    expect(rejected.code).toBe(65);
    expect(rejected.stderr).toMatch(/has no "version"/);
    const live = await doctor(["--metadata", "-", "--stats"]);
    expect(live.code).toBe(2);
    expect(live.stderr).toMatch(/can't be combined with --stats/);
  });

  it("runs every rule on a database snapshot", () => {
    const rule = (code: string) => ({ code, title: code });
    const partial = fromMetadata(snapshot.generator);
    expect(skippedForMetadata(snapshot, rule("BS103"), "")).toBeUndefined();
    expect(skippedForMetadata(partial, rule("BS501"), "")).toBeUndefined();
    expect(skippedForMetadata(partial, rule("BS103"), "help")).toMatchObject({
      code: "BS103",
      severity: "info",
      help: "help",
      message: expect.stringMatching(/^Skipped/),
    });
  });
});
