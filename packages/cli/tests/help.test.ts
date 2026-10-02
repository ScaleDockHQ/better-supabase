import { describe, expect, it } from "vitest";

import { commandNames, help } from "../src/run.ts";

describe("help", () => {
  it("lists the commands and the global options", async () => {
    expect(await help()).toMatchSnapshot();
  });

  it.each(commandNames())("documents %s", async (command) => {
    expect(await help(command)).toMatchSnapshot();
  });
});
