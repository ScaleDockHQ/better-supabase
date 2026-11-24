import type { DbStats } from "better-supabase";

/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
/* oxlint-disable vitest/prefer-each -- Playwright has no test.each; the loop
   generates one case per action of the manifest (1 finding). */
import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";

import { ACTIONS } from "./actions.manifest";
import { perfUser, recordPerf, signIn } from "./support/example-session";

// Calls every action of the manifest once, as a browser would (a POST with the
// action's id in `Next-Action`), and records the database calls, waves and time
// of the request from the debug route, by action name. The ids come from the
// build's server reference manifest. Also records how many actions the build
// has and how many the manifest covers. Needs the production build with the
// testing API (see instant-nav.rig.md).

interface ReferenceEntry {
  readonly filename: string;
  readonly exportedName: string;
}

function actionIds(): ReadonlyMap<string, string> {
  const manifest = JSON.parse(
    readFileSync(".next/server/server-reference-manifest.json", "utf-8"),
    // SAFETY: Next.js writes this file as { node: { [id]: entry } }.
  ) as { node: Record<string, ReferenceEntry> };

  return new Map(
    Object.entries(manifest.node).flatMap(([id, entry]) => {
      const file = entry.filename.replace(/^.*\/src\//, "");

      return file.endsWith("-actions.ts")
        ? [[`${file}#${entry.exportedName}`, id] as const]
        : [];
    }),
  );
}

const ids = actionIds();

test.beforeEach(async ({ page }) => {
  await signIn(page, perfUser());
});

test("the manifest lists the actions the build has", () => {
  const covered = ACTIONS.filter((action) =>
    ids.has(`${action.file}#${action.name}`),
  ).length;

  recordPerf("actions-coverage.json", "all", {
    actions: ids.size,
    covered,
    uncovered: ids.size - covered,
  });
  expect(covered).toBe(ACTIONS.length);
});

for (const action of [...ACTIONS].toSorted(
  (a, b) => Number(a.mutates) - Number(b.mutates),
)) {
  test(`${action.name} database cost`, async ({ page }) => {
    const id = ids.get(`${action.file}#${action.name}`);
    expect(id).toBeDefined();

    await page.goto(action.page);

    const reply = await page.request.post(action.page, {
      headers: {
        "Next-Action": id ?? "",
        "Content-Type": "text/plain;charset=UTF-8",
        Accept: "text/x-component",
      },
      data: JSON.stringify(
        action.resolve ? await action.resolve() : action.args,
      ),
    });

    const requestId = reply.headers()["x-bsb-request-id"];
    const statsPath = reply.headers()["x-bsb-stats"];

    expect(requestId).toBeDefined();

    const stats = await page.request.get(statsPath ?? "");
    // SAFETY: the debug route answers with a DbStats object.
    const body = (await stats.json()) as DbStats;

    recordPerf(`actions-${perfUser()}.json`, action.name, {
      status: reply.status(),
      calls: body.calls,
      waves: body.waves,
      ms: body.ms,
      verifications: body.verifications,
      adminCalls: body.adminCalls,
      tables: body.tables.length,
    });
  });
}
