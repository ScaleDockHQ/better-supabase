import type { TestSpecification } from "vitest/node";

import { relative } from "node:path";
import { argv, env } from "node:process";
import { fileURLToPath } from "node:url";
import { defineConfig, mergeConfig } from "vitest/config";
import { BaseSequencer } from "vitest/node";

import { assignShard, readDurations } from "./tests/unit-shard.ts";

const durations = readDurations(
  fileURLToPath(new URL("tests/unit-durations.json", import.meta.url)),
);

/** Packs `--shard` by the measured file durations instead of by path hash. */
class DurationSequencer extends BaseSequencer {
  override shard(files: TestSpecification[]): Promise<TestSpecification[]> {
    const shard = this.ctx.config.shard;

    if (shard === undefined) {
      return Promise.resolve(files);
    }

    return Promise.resolve(
      assignShard(
        files,
        (spec) =>
          relative(this.ctx.config.root, spec.moduleId).replaceAll("\\", "/"),
        durations,
        shard.index,
        shard.count,
      ),
    );
  }
}

// A CI shard covers part of the code, so only `vitest --merge-reports --coverage` checks the
// thresholds. autoUpdate edits the defineConfig below, so the real numbers stay there.
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
      projects: [
        {
          extends: true,
          test: {
            name: "unit",
            include: ["tests/**/*.test.ts"],
            exclude: ["tests/**/*.integration.test.ts"],
            // The first test in a CLI file pays the lazy command imports; with coverage on and
            // every workspace testing in parallel, that passes the 5 second default.
            testTimeout: 20_000,
            // Only this project: integration shards stay on Vitest's path hash.
            sequence: { sequencer: DurationSequencer },
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
