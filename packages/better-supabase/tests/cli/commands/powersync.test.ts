import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { configuredTasks } from "../../../src/cli/commands/gen-pipeline.ts";
import { runPowerSync } from "../../../src/cli/commands/powersync.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const BLOCKS = {
  memberships: {},
  organizations: {},
  notifications: {},
  attachments: {},
};

describe("powersync streams", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-powersync-"));
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(join(root, "supabase/config.toml"), "");
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const config = (instances?: string[]) =>
    resolveConfig(
      {
        blocks: BLOCKS,
        ...(instances === undefined
          ? {}
          : { gen: { powersync: { instances } } }),
      },
      root,
    );

  const now = () => new Date("2026-10-25T12:00:00Z");

  const migrations = async () =>
    (await readdir(join(root, "supabase/migrations"))).filter((name) =>
      name.endsWith("_powersync_publication.sql"),
    );

  it("asks for the instances when gen.powersync is unset", async () => {
    expect(await runPowerSync(config(), {}, now)).toMatchObject({
      code: 1,
      errorCode: "config_invalid",
    });
  });

  it("refuses a block that can't sync and an unknown key", async () => {
    expect(
      await runPowerSync(config(["organizations"]), {}, now),
    ).toMatchObject({
      code: 1,
      error: expect.stringContaining("organizations installs organizations"),
    });

    expect(await runPowerSync(config(["inbox"]), {}, now)).toMatchObject({
      code: 1,
      error: "inbox is not a block in the config.",
    });
  });

  it("writes the streams, the schema and one publication migration", async () => {
    const settings = config(["notifications", "attachments"]);
    expect(configuredTasks(settings)).toContain("powersync");

    const first = await runPowerSync(settings, {}, now);
    expect(first.code).toBe(0);

    expect(
      await readFile(join(root, "powersync/sync-streams.yaml"), "utf-8"),
    ).toContain("notifications_recipients:");

    expect(
      await readFile(join(root, "powersync/schema.ts"), "utf-8"),
    ).toContain("export const blockTables");

    expect(await migrations()).toHaveLength(1);

    await runPowerSync(settings, {}, now);
    expect(await migrations()).toHaveLength(1);

    expect(await runPowerSync(settings, { check: true }, now)).toMatchObject({
      code: 0,
    });
  });

  it("adds a new migration when the synced tables change", async () => {
    await runPowerSync(config(["notifications"]), {}, now);

    const later = () => new Date("2026-10-26T12:00:00Z");

    expect(
      await runPowerSync(
        config(["notifications", "attachments"]),
        { check: true },
        later,
      ),
    ).toMatchObject({ code: 1 });

    await runPowerSync(config(["notifications", "attachments"]), {}, later);
    expect(await migrations()).toHaveLength(2);
  });

  it("takes --instance and --out over the config", async () => {
    const result = await runPowerSync(
      config(["notifications", "attachments"]),
      { instance: "notifications", out: "sync" },
      now,
    );

    expect(result.code).toBe(0);

    expect(
      await readFile(join(root, "sync/sync-streams.yaml"), "utf-8"),
    ).not.toContain("attachments:");
  });
});
