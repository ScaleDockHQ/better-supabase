import { describe, expect, it } from "vitest";

import { builtinCommands } from "../../src/cli/builtin-commands.ts";
import { findSpec, specPaths } from "../../src/cli/core/manifest.ts";
import { commandArgs } from "../../src/cli/core/parse.ts";
import { help } from "../../src/cli/core/run.ts";
import { VERSION } from "../../src/cli/version.ts";

// The snapshots must survive a release, which bumps VERSION.
async function usage(command?: string): Promise<string> {
  return (await help(command)).replaceAll(`v${VERSION}`, "v<version>");
}

describe("help", () => {
  it("lists the commands and the global options", async () => {
    expect(await usage()).toMatchSnapshot();
  });

  it.each(
    [...builtinCommands().loaders].map(([path, load]) => [path, load] as const),
  )("reads the %s meta from the manifest", async (path, load) => {
    const { meta } = await load();
    const spec = findSpec(path.split(" "));
    expect(meta).toEqual({ name: spec?.name, description: spec?.description });
    expect(await help(path)).toContain(`\n\n${spec?.description}\n`);
  });

  it.each(
    [...builtinCommands().loaders].map(([path, load]) => [path, load] as const),
  )(
    "prints each option of %s with its exact description",
    async (path, load) => {
      const args = await commandArgs(await load());
      const lines = (await help(path)).split("\n");

      const wrong = Object.entries(args).flatMap(([name, definition]) => {
        if (definition.type === "positional" || !definition.description) {
          return [];
        }

        const negated =
          definition.type === "boolean" && definition.default === true;

        const flag = negated ? `--no-${name}` : `--${name}`;

        const description =
          negated && "negativeDescription" in definition
            ? definition.negativeDescription
            : definition.description;

        const line = lines.find((each) =>
          new RegExp(`^  (?:-\\w, )?${flag}(?: |$)`).test(each),
        );

        return line?.endsWith(`  ${description}`) ? [] : [`${flag}: ${line}`];
      });

      expect(wrong).toEqual([]);
    },
  );

  it.each(specPaths().map((path) => path.join(" ")))(
    "documents %s",
    async (command) => {
      expect(await usage(command)).toMatchSnapshot();
    },
  );
});
