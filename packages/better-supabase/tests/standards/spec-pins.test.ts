import { existsSync, readdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const HERE = import.meta.dirname;
/** The CLI's conformance tests (doctor's SARIF, schemas, keys and skills). */
const CLI = resolve(HERE, "../cli/standards");
const DIRS = [HERE, CLI];
const testFiles = (dir: string): string[] =>
  readdirSync(dir).filter((file) => file.endsWith(".test.ts"));
const PAGE = resolve(
  HERE,
  "../../../../apps/docs/content/docs/standards/index.mdx",
);

interface Row {
  readonly standard: string;
  readonly posture: string;
  readonly tests: readonly string[];
}

async function registry(): Promise<Row[]> {
  const page = await readFile(PAGE, "utf8");
  const table = page.slice(
    page.indexOf("## Registry"),
    page.indexOf("## Pins"),
  );
  return table
    .split("\n")
    .filter((line) => line.startsWith("| ["))
    .map((line) => {
      const cells = line
        .split(/(?<!\\)\|/)
        .slice(1, -1)
        .map((cell) => cell.trim());
      return {
        standard: cells[0]!,
        posture: cells[1]!,
        tests: [...(cells[3] ?? "").matchAll(/`([^`]+\.test\.ts)`/g)].map(
          (match) => match[1]!,
        ),
      };
    });
}

describe("standards registry", async () => {
  const rows = await registry();
  const adopted = rows.filter((row) => row.posture.startsWith("Adopted"));

  it("parses the registry table", () => {
    expect(adopted.length).toBeGreaterThan(20);
  });

  it.each(adopted.map((row) => [row.standard, row] as const))(
    "%s names a conformance test that exists",
    (_name, row) => {
      expect(row.tests.length).toBeGreaterThan(0);
      expect(
        row.tests.filter(
          (test) => !DIRS.some((dir) => existsSync(join(dir, test))),
        ),
      ).toEqual([]);
    },
  );

  it("tracked standards name no test", () => {
    for (const row of rows.filter((item) => item.posture === "Tracked"))
      expect(row.tests).toEqual([]);
  });

  it("every test file in tests/standards backs a registry row", () => {
    const named = new Set(adopted.flatMap((row) => row.tests));
    const files = DIRS.flatMap(testFiles).filter(
      (file) => !["sources.test.ts", "spec-pins.test.ts"].includes(file),
    );
    expect(files.filter((file) => !named.has(file))).toEqual([]);
  });
});

describe("SPEC_PINS", async () => {
  const page = await readFile(PAGE, "utf8");
  const suite = (
    await Promise.all(
      DIRS.flatMap((dir) =>
        testFiles(dir)
          .filter((file) => file !== "spec-pins.test.ts")
          .map((file) => readFile(join(dir, file), "utf8")),
      ),
    )
  ).join("\n");

  it.each(Object.keys(SPEC_PINS))(
    "%s is documented on the standards page",
    (key) => {
      expect(page).toContain(`SPEC_PINS.${key};`);
    },
  );

  it.each(Object.keys(SPEC_PINS))(
    "%s is asserted by a conformance test",
    (key) => {
      expect(suite).toContain(`SPEC_PINS.${key}`);
    },
  );

  it("the page lists no pin that the code lacks", () => {
    const listed = [...page.matchAll(/^SPEC_PINS\.([a-zA-Z]+);/gm)].map(
      (match) => match[1],
    );
    expect(new Set(listed)).toEqual(new Set(Object.keys(SPEC_PINS)));
  });
});
