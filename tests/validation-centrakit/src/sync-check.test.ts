import { introspect, run, serializeSnapshot } from "better-supabase/cli";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, withCentraKit } from "./stack.ts";

const live = await reachable();
const fixture = fileURLToPath(new URL("..", import.meta.url));

describe("the committed module files", () => {
  it("are what sql sync writes for the config and the provider snapshot", async () => {
    const result = await run(["sql", "sync", "--check", "--cwd", fixture]);

    expect(result).toMatchObject({ code: 0, stderr: "" });
  });
});

describe.skipIf(!live)("doctor on the installed fixture", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it("reports no findings", async () => {
    const dir = await mkdtemp(join(tmpdir(), "centrakit-doctor-"));

    try {
      await withCentraKit(pool, async (s) => {
        await s.as("service");

        const snapshot = await introspect(s.client, [
          "centrakit",
          "better_supabase",
        ]);

        await writeFile(
          join(dir, "snapshot.json"),
          serializeSnapshot(snapshot),
        );
      });

      // BS303 compares the app's generated client with the database; the
      // fixture has no app code to generate. BS700 and BS701 report the
      // host's shared memory, which other local stacks fill.
      const result = await run([
        "doctor",
        "--json",
        "--ignore",
        "BS303,BS700,BS701",
        "--snapshot",
        join(dir, "snapshot.json"),
        "--cwd",
        fixture,
      ]);

      const { data: report } = JSON.parse(result.stdout) as {
        readonly data: {
          readonly findings: readonly {
            readonly code: string;
            readonly severity: string;
            readonly message: string;
          }[];
        };
      };

      // The adopt options that keep CentraKit's own token storage, secret
      // column, audit values and event sources are the only warnings.
      // The shared stack also has the Next.js example's comments and reactions
      // modules, which the fixture doesn't install, so doctor BS213 doesn't
      // know comments.deleted_at is a soft-delete column.
      expect(
        report.findings
          .filter((finding) => finding.severity !== "info")
          .filter(
            (finding) =>
              !(
                finding.code === "BS213" &&
                finding.message.includes("reaction_subject_visible")
              ),
          )
          .map((finding) => `${finding.severity} ${finding.code}`),
      ).toEqual(Array.from({ length: 5 }, () => "warning BS314"));
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
