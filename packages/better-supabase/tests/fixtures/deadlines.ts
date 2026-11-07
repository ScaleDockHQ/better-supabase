import { readdirSync, readFileSync } from "node:fs";

import type {
  DeadlineCounting,
  DeadlineGroupResult,
  RuleVersionContent,
} from "../../src/sql/modules/deadlines-values.ts";

/** One case of a golden fixture: facts in, the results expected out. */
export interface GoldenCase {
  readonly name: string;
  readonly facts: Readonly<Record<string, unknown>>;
  readonly asOf: string;
  readonly group?: string;
  /** Replaces the version's counting block for this case; null drops it. */
  readonly counting?: DeadlineCounting | null;
  readonly expect: readonly DeadlineGroupResult[];
}

/**
 * A golden fixture: a rule set version and its cases
 * (`tests/fixtures/deadlines`).
 */
export interface GoldenFixture {
  readonly name: string;
  readonly content: RuleVersionContent;
  readonly cases: readonly GoldenCase[];
  /** Days and whether the version's counting block makes them holidays. */
  readonly holidays?: readonly {
    readonly date: string;
    readonly holiday: boolean;
  }[];
}

const DIR = new URL("deadlines/", import.meta.url);

/** Every golden fixture, by file name. */
export const GOLDEN: readonly GoldenFixture[] = readdirSync(DIR)
  .filter((file) => file.endsWith(".json"))
  .toSorted()
  .map((file) => ({
    name: file.replace(/\.json$/u, ""),
    // SAFETY: the fixtures are written to this shape by hand and checked by the golden tests.
    ...(JSON.parse(readFileSync(new URL(file, DIR), "utf-8")) as Omit<
      GoldenFixture,
      "name"
    >),
  }));

/** A case's version: the fixture's, with the case's counting block. */
export function contentOf(
  fixture: GoldenFixture,
  test: GoldenCase,
): RuleVersionContent {
  if (test.counting === undefined) {
    return fixture.content;
  }

  const { counting: _counting, ...rest } = fixture.content;

  return test.counting === null ? rest : { ...rest, counting: test.counting };
}
