import { describe, expect, it } from "vitest";

import plugin from "./oxlint/i18n-extract.ts";

/** The parts of the ESTree nodes the rule reads. */
interface Node {
  readonly type: string;
  readonly name?: string;
  readonly left?: Node;
  readonly right?: Node;
  readonly key?: Node;
  readonly value?: Node;
  readonly argument?: Node;
  readonly properties?: readonly Node[];
}

const id = (name: string): Node => ({ type: "Identifier", name });

const reported = (params: readonly Node[]): readonly unknown[] => {
  const found: unknown[] = [];

  const visitors = plugin.rules["no-translator-parameter"].create({
    report: ({ node }) => found.push(node),
  });

  visitors.ArrowFunctionExpression({ type: "ArrowFunctionExpression", params });

  return found;
};

describe("i18n-extract/no-translator-parameter", () => {
  it("reports a translator parameter, plain, defaulted or destructured", () => {
    const t = id("t");

    expect(reported([t, id("status")])).toEqual([t]);
    expect(
      reported([{ type: "AssignmentPattern", left: t, right: id("x") }]),
    ).toEqual([t]);
    expect(
      reported([
        {
          type: "ObjectPattern",
          properties: [
            { type: "Property", key: id("t"), value: t },
            { type: "RestElement", argument: id("rest") },
          ],
        },
      ]),
    ).toEqual([t]);
  });

  it("leaves other parameters alone", () => {
    expect(reported([id("translate"), id("tenant")])).toEqual([]);
  });
});
