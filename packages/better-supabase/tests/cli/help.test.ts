import { describe, expect, it } from "vitest";

import { commandDescriptions, commandNames, help } from "../../src/cli/run.ts";

describe("help", () => {
  it("lists the commands and the global options", async () => {
    expect(await help()).toMatchSnapshot();
  });

  it.each([...commandDescriptions()])(
    "shows the %s description from the command in the root usage",
    async (name, description) => {
      const usage = await help(name);
      expect(usage.split("\n")[0]).toContain(description);
    },
  );

  it.each(commandNames())("documents %s", async (command) => {
    expect(await help(command)).toMatchSnapshot();
  });
});
