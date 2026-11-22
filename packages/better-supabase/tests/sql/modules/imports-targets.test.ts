import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const render = (targetConvention: unknown): unknown =>
  renderBlocks(["imports"], {
    modules: { imports: { options: { targetConvention } } },
  });

describe("imports targetConvention", () => {
  it("must be an object", () => {
    expect(() => render(3)).toThrow(
      "blocks['imports'].options.targetConvention must be { schema?, write?, updatedAt? }",
    );
  });

  it("needs text for each name", () => {
    expect(() => render({ write: "" })).toThrow(
      "blocks['imports'].options.targetConvention.write must be text",
    );
  });
});
