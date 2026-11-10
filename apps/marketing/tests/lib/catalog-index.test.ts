import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { blockSummariesSchema } from "../../lib/block-filter";
import { blockSummaries } from "../../lib/blocks";
import { recipeSummariesSchema } from "../../lib/recipe-filter";
import { availableRecipes, recipeSummary } from "../../lib/recipes";

// `/blocks/index.json` and `/recipes/index.json` serve these lists, and the
// search and the filters check the response against the schemas.
describe("catalog index documents", () => {
  it("serves every block summary in the shape the search expects", () => {
    const parsed = v.parse(
      blockSummariesSchema,
      JSON.parse(JSON.stringify(blockSummaries())),
    );

    expect(parsed).toHaveLength(blockSummaries().length);
  });

  it("serves every available recipe in the shape the filters expect", () => {
    const parsed = v.parse(
      recipeSummariesSchema,
      JSON.parse(JSON.stringify(availableRecipes.map(recipeSummary))),
    );

    expect(parsed).toHaveLength(availableRecipes.length);
  });
});
