import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { emitHooks } from "../../../src/cli/gen/hooks.ts";
import { emitRecords } from "../../../src/cli/gen/records.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

const ROOT = fileURLToPath(new URL("../../../../../", import.meta.url));

const OXFMT = join(
  dirname(createRequire(import.meta.url).resolve("oxfmt/package.json")),
  "bin/oxfmt",
);

/** The file as the repo's formatter prints it, under an example app's path. */
function formatted(path: string, contents: string): string {
  return execFileSync(
    process.execPath,
    [OXFMT, `--stdin-filepath=apps/examples/nextjs/${path}`],
    { cwd: ROOT, input: contents, encoding: "utf-8" },
  );
}

describe("generated files the formatter leaves alone", () => {
  it("writes records/ as oxfmt prints it", () => {
    const config = resolveConfig(
      {
        subjects: {
          customer: { table: "customers" },
          calendar_event: { table: "calendar_events" },
          project: {
            table: "projects",
            versions: { columns: ["name"], auto: true },
          },
        },
        blocks: {
          memberships: {},
          permissions: {},
          comments: {},
          tags: {},
          versions: {},
          sla: {},
          "share-links": {},
          "billable-time": {},
          "support-notes": { block: "comments" },
        },
      },
      "/project",
    );

    const files = emitRecords(config);

    expect(files.length).toBeGreaterThan(1);

    const output = Object.fromEntries(
      files.map((file) => [file.path, file.contents]),
    );

    expect(
      Object.fromEntries(
        files.map((file) => [file.path, formatted(file.path, file.contents)]),
      ),
    ).toEqual(output);
  });

  it("writes hooks.ts as oxfmt prints it, whatever the name lengths", () => {
    const config = resolveConfig({ adapters: ["next"] }, "/project");

    const file = emitHooks(config, [
      "x",
      "notes",
      "contacts",
      "clientNotes",
      "customersWithOwner",
      "organizationMembershipInvitations",
      "organizationMembershipInvitationReminderSchedules",
      "line-items",
    ]);

    expect(file).toBeDefined();
    expect(formatted(file?.path ?? "", file?.contents ?? "")).toBe(
      file?.contents,
    );
  });

  it.each(["./scope", "@/lib/scope", "app-scope", "zz-scope"])(
    "places the gen.hooks.select import from %s where oxfmt sorts it",
    (module) => {
      const config = resolveConfig(
        {
          adapters: ["next"],
          gen: { hooks: { select: { module, export: "scopedSelect" } } },
        },
        "/project",
      );

      const file = emitHooks(config, ["notes", "customersWithOwner"]);

      expect(formatted(file?.path ?? "", file?.contents ?? "")).toBe(
        file?.contents,
      );
    },
  );
});
