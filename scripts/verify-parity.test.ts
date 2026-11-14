import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

// `pnpm verify` is the local gate and `verify.yml` is the CI one. A task in the first and not the
// second passes in CI while failing locally (`check:naming` did).
const pkg = JSON.parse(readFileSync("package.json", "utf-8")) as {
  scripts: Record<"verify", string>;
};

const workflow = readFileSync(".github/workflows/verify.yml", "utf-8");

const verifyTasks = pkg.scripts.verify.split("&&").flatMap((command) => {
  const match = /^\s*turbo run (.*)$/.exec(command);

  return (
    match?.[1]?.split(/\s+/).filter((word) => word && !word.startsWith("--")) ??
    []
  );
});

const escape = (task: string): string =>
  task.replaceAll(/[:.]/g, String.raw`\$&`);

describe("verify.yml", () => {
  it("runs every task of `pnpm verify`", () => {
    const missing = verifyTasks.filter(
      (task) =>
        !new RegExp(`(^|[\\s:])${escape(task)}(\\s|$)`, "m").test(workflow),
    );

    expect(verifyTasks.length).toBeGreaterThan(20);
    expect(missing).toEqual([]);
  });
});
