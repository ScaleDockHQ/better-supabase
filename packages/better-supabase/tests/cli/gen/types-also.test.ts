import { describe, expect, it } from "vitest";

import { renderFiles } from "../../../src/cli/gen/render.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

const render = async (also: readonly string[] | undefined) =>
  renderFiles(
    resolveConfig(
      {
        gen: {
          file: "src/db/generated.ts",
          ...(also === undefined ? {} : { types: { also } }),
        },
      },
      "/project",
    ),
    await loadFixtureSnapshot(),
    { extensions: false },
  );

describe("gen.types.also", () => {
  it("writes database.types.ts to each extra file", async () => {
    const files = await render([
      "../mobile/src/database.types.ts",
      "packages/shared/database.types.ts",
    ]);

    const main = files.find((file) => file.path === "src/db/database.types.ts");

    expect(main?.contents).toContain("export type Database");

    for (const path of [
      "../mobile/src/database.types.ts",
      "packages/shared/database.types.ts",
    ]) {
      expect(files.find((file) => file.path === path)?.contents).toBe(
        main?.contents,
      );
    }
  });

  it("does not write a file twice and writes nothing by default", async () => {
    const twice = await render(["src/db/database.types.ts"]);

    expect(
      twice.filter((file) => file.path === "src/db/database.types.ts"),
    ).toHaveLength(1);

    const none = await render(undefined);

    expect(none.map((file) => file.path)).not.toContain(
      "packages/shared/database.types.ts",
    );
  });
});
