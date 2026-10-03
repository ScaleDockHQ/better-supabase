import { describe, expect, it } from "vitest";

import { commandDescriptions, commandNames, help } from "../../src/cli/run.ts";
import { VERSION } from "../../src/cli/version.ts";

// The snapshots must survive a release, which bumps VERSION.
async function usage(command?: string): Promise<string> {
  return (await help(command)).replaceAll(`v${VERSION}`, "v<version>");
}

describe("help", () => {
  it("lists the commands and the global options", async () => {
    expect(await usage()).toMatchSnapshot();
  });

  it.each([...commandDescriptions()])(
    "shows the %s description from the command in the root usage",
    async (name, description) => {
      const text = await help(name);
      expect(text.split("\n")[0]).toContain(description);
    },
  );

  it.each(commandNames())("documents %s", async (command) => {
    expect(await usage(command)).toMatchSnapshot();
  });
});
