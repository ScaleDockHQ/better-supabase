import { run } from "better-supabase/cli";
import { readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, ROOT } from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

interface Snapshot {
  readonly generator: {
    readonly columns: readonly {
      readonly schema: string;
      readonly table: string;
      readonly name: string;
    }[];
  };
}

/** The columns of `public.<view>` in the committed snapshot. */
const viewColumns = async (view: string): Promise<string[]> => {
  const snapshot = JSON.parse(
    await readFile(join(ROOT, "snapshot.json"), "utf-8"),
  ) as Snapshot;

  return snapshot.generator.columns
    .filter((column) => column.schema === "public" && column.table === view)
    .map((column) => column.name)
    .toSorted();
};

/** The names a stream's select list gives its columns, by stream. */
const streamColumns = (yaml: string): Map<string, string[]> => {
  const streams = new Map<string, string[]>();
  let current = "";

  for (const line of yaml.split("\n")) {
    const named = /^ {2}(\w+):$/.exec(line);

    if (named !== null) {
      current = named[1]!;
    }

    const query = /^ {4}query: "SELECT (.+?) FROM /.exec(line);

    if (query !== null) {
      streams.set(
        current,
        query[1]!
          .split(", ")
          .map((item) => /(?: AS )?(\w+)$/.exec(item)![1]!)
          .toSorted(),
      );
    }
  }

  return streams;
};

describe("PowerSync streams over the projection views", () => {
  it(
    "select the columns the app's views select",
    { timeout: 60_000 },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);

      const result = await run([
        "powersync",
        "streams",
        "--cwd",
        dir,
        "--instance",
        "attachments,memberships,teams,profiles",
        "--out",
        "powersync",
      ]);

      expect(result).toMatchObject({ code: 0 });

      const streams = streamColumns(
        await readFile(join(dir, "powersync/sync-streams.yaml"), "utf-8"),
      );

      for (const [stream, view] of [
        ["attachments", "job_attachments"],
        ["memberships_memberships", "memberships"],
        ["teams_teams", "teams"],
        ["teams_members", "team_members"],
        ["profiles", "profiles"],
      ] as const) {
        const columns = await viewColumns(view);

        // PowerSync needs an id on every row, so a table keyed by two columns
        // streams a composite one the view doesn't have.
        expect(
          Object.fromEntries([[stream, streams.get(stream)]]),
        ).toStrictEqual({
          [stream]: columns.includes("id")
            ? columns
            : [...columns, "id"].toSorted(),
        });
      }

      // The organizations stream keeps the switcher's columns, a subset of
      // the view's.
      const organizations = await viewColumns("organizations");

      for (const column of streams.get("memberships_organizations")!) {
        expect(organizations).toContain(column);
      }
    },
  );
});
