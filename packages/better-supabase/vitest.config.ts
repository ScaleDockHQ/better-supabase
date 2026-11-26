import type { TestSpecification } from "vitest/node";

import { relative } from "node:path";
import { argv, env } from "node:process";
import { fileURLToPath } from "node:url";
import { defineConfig, mergeConfig } from "vitest/config";
import { BaseSequencer } from "vitest/node";

import { assignShard, getDurations } from "./tests/unit-shard.ts";

const durations = getDurations(
  fileURLToPath(new URL("tests/unit-durations.json", import.meta.url)),
);

const fileOf = (spec: TestSpecification, root: string): string =>
  relative(root, spec.moduleId).replaceAll("\\", "/");

const unitOnly = (files: readonly TestSpecification[]): boolean =>
  files.every((spec) => spec.project.name === "unit");

/**
 * Packs the unit project's `--shard` by the measured file durations instead of
 * by path hash, and runs the longest file first. Integration files share one
 * database, so they keep Vitest's order.
 */
class DurationSequencer extends BaseSequencer {
  override shard(files: TestSpecification[]): Promise<TestSpecification[]> {
    const shard = this.ctx.config.shard;

    if (shard === undefined || !unitOnly(files)) {
      return super.shard(files);
    }

    return Promise.resolve(
      assignShard(
        files,
        (spec) => fileOf(spec, this.ctx.config.root),
        durations,
        shard.index,
        shard.count,
      ),
    );
  }

  override sort(files: TestSpecification[]): Promise<TestSpecification[]> {
    if (!unitOnly(files)) {
      return BaseSequencer.prototype.sort.call(this, files);
    }

    return Promise.resolve(
      assignShard(
        files,
        (spec) => fileOf(spec, this.ctx.config.root),
        durations,
        1,
        1,
      ),
    );
  }
}

// A CI shard covers part of the code, so only `vitest --merge-reports --coverage` checks the
// thresholds.
const none = { statements: 0, lines: 0, functions: 0, branches: 0 };

const shard = argv.some((arg) => arg.startsWith("--shard"))
  ? {
      test: {
        coverage: {
          thresholds: { ...none, "src/cli/**": none, autoUpdate: false },
        },
      },
    }
  : {};

export default mergeConfig(
  defineConfig({
    test: {
      // Node 24 has no Temporal; Node 26 ignores the polyfill.
      // @chat-adapter/tests/setup registers the matchers its contract runners use.
      setupFiles: [
        "./tests/setup/temporal.ts",
        "./tests/setup/connection.ts",
        "@chat-adapter/tests/setup",
      ],
      // The contract runners in @chat-adapter/tests call describe at import time; loaded
      // natively, they get a second vitest instance with no runner.
      server: { deps: { inline: ["@chat-adapter/tests"] } },
      // On a laptop, one worker per core is slower: the workers starve each other and the
      // other Turbo tasks. CI runners have few cores and nothing else running.
      maxWorkers: env.CI ? undefined : "50%",
      // Vitest reads the sequencer from the root config only.
      sequence: { sequencer: DurationSequencer },
      projects: [
        {
          extends: true,
          test: {
            name: "unit",
            include: ["tests/**/*.test.ts"],
            exclude: ["tests/**/*.integration.test.ts"],
            // The first test in a CLI file pays the lazy command imports; with coverage on and
            // every workspace testing in parallel, that passes the 5 second default.
            // A beforeEach that runs a CLI command pays the same imports, and a hook has its own
            // 10 second default (remove.test.ts timed out there on a loaded runner).
            testTimeout: 20_000,
            hookTimeout: 20_000,
            typecheck: {
              enabled: true,
              include: ["tests/**/*.test-d.ts"],
              ignoreSourceErrors: true,
            },
          },
        },
        {
          extends: true,
          test: {
            name: "integration",
            include: ["tests/**/*.integration.test.ts"],
            globalSetup: ["./tests/integration/global-setup.ts"],
            // The suites share one database; counts must not race with writes.
            fileParallelism: false,
            // The doctor suite runs the whole rule set against the stack and took 5.2 s on a CI
            // runner (main, #1130 merge), just past the 5 second default.
            testTimeout: 20_000,
          },
        },
      ],
      coverage: {
        provider: "v8",
        include: ["src/**/*.ts"],
        exclude: ["src/cli/bin.ts"],
        // Nothing in CI reads the report files.
        reporter: env.CI
          ? ["text-summary"]
          : ["text-summary", "json-summary", "json", "html"],
        // Unit tests alone must hold these; the floor is 90/90/90/80.
        // The numbers are ceilings. Coverage that grows does not rewrite
        // this file, so a pull request does not conflict on them.
        // The top-level numbers count every file, CLI included; the src/cli set
        // also holds the CLI to its own numbers.
        // Lines sit below statements because curly puts every if body on its
        // own line.
        thresholds: {
          statements: 97,
          lines: 97,
          functions: 98,
          branches: 91,
          "src/cli/**": {
            statements: 97,
            lines: 97,
            functions: 98,
            branches: 91,
          },
          autoUpdate: false,
        },
      },
    },
  }),
  shard,
);
