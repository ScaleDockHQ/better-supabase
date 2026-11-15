import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { PromptSummary } from "../../src/blocks/prompts/index.ts";
import type { PageOptions } from "../../src/core/block-helpers.ts";
import type { Result } from "../../src/core/result.ts";

import { createAnnouncements } from "../../src/blocks/announcements/index.ts";
import { announcementListSurface } from "../../src/blocks/announcements/lists.ts";
import { createPrompts } from "../../src/blocks/prompts/index.ts";
import { promptListSurface } from "../../src/blocks/prompts/lists.ts";
import { createReminders } from "../../src/blocks/reminders/index.ts";
import { reminderListSurface } from "../../src/blocks/reminders/lists.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { tagListSurface } from "../../src/blocks/tags/lists.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MISSING = "00000000-0000-4000-8000-000000000000";

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.kind);

/** Every declared sort in both directions, with `q` when the entity has it. */
async function everySort(
  surface: {
    readonly sorts?: readonly string[];
    readonly search?: boolean | readonly string[];
  },
  page: (options: PageOptions) => PromiseLike<Result<unknown>>,
): Promise<void> {
  for (const by of surface.sorts ?? []) {
    for (const direction of ["asc", "desc"] as const) {
      const q = surface.search === undefined ? {} : { q: "x" };

      expect(hint(await page({ sort: { by, direction }, ...q }))).toBe("ok");
    }
  }
}

describe.skipIf(!live)(
  "the F13 and F14 block lists follow the contract",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });

    afterAll(() => pool.end());

    it("pages tags, announcements and prompts", async () => {
      const s = await BlockSession.open(pool);

      try {
        const owner = await s.user("f13-a-owner");
        await s.install(["organizations", "tags", "announcements", "prompts"]);
        const org = await s.organization(owner);

        await s.service();

        const announcements = createAnnouncements({
          transport: sqlTransport(s.sql),
        });

        const prompts = createPrompts({ transport: sqlTransport(s.sql) });

        // The seed publishes announcements, and rows made in one transaction
        // share their start time, so only `title` has a stable reverse order.
        await s.client.query("delete from better_supabase.announcements");

        const severities = ["info", "info", "warning", "warning", "critical"];

        for (const [index, severity] of severities.entries()) {
          await announcements
            .publish({
              title: `${index < 2 ? "Holiday" : "Other"} notice ${String(index)}`,
              severity: severity as "info" | "warning" | "critical",
            })
            .orThrow();
        }

        // The SQL transport sends a JS array as a Postgres array, not jsonb.
        for (const [index, label] of ["a", "b", "c"].entries()) {
          await s.value(
            "better_supabase.create_prompt_version($1, $2, $3, $4::jsonb, $5)",
            [
              `${index < 2 ? "holiday" : "other"}-${label}`,
              "Hi",
              org,
              "[]",
              index === 0 ? "production" : null,
            ],
          );
        }

        // Distinct version counts give `versionCount` a stable order to reverse.
        for (const [name, versions] of [
          ["holiday-a", 2],
          ["holiday-b", 3],
        ] as const) {
          for (let at = 1; at < versions; at += 1) {
            await s.value(
              "better_supabase.create_prompt_version($1, $2, $3, $4::jsonb)",
              [name, `Hi ${String(at)}`, org, "[]"],
            );
          }
        }

        await testBlockList({
          name: "announcements",
          target: {
            page: (options) => announcements.page(options),
            count: (options) => announcements.count(options),
            facets: (options) => announcements.facets(options),
            get: (id) => announcements.get(id),
          },
          rows: 5,
          sorts: ["title"],
          facets: { severity: { info: 2, warning: 2, critical: 1 } },
          arrayFilter: { column: "severity", values: ["info", "critical"] },
          search: "Holiday",
        });

        await testBlockList({
          name: "prompts",
          target: {
            page: (options) =>
              prompts.page({ ...options, organizationId: org }),
            count: (options) =>
              prompts.count({ ...options, organizationId: org }),
            // The kit only asks whether the row exists, so a found prompt stands in
            // for its summary.
            get: (name) =>
              prompts
                .getPrompt({ name, organizationId: org })
                // SAFETY: the kit reads `ok` and the error kind, not the row.
                .map((prompt) => prompt as unknown as PromptSummary),
          },
          rows: 3,
          sorts: ["name", "versionCount"],
          arrayFilter: { column: "name", values: ["holiday-a", "other-c"] },
          search: "holiday",
          idOf: (item) => item.name,
        });

        expect(
          (
            await prompts.page({
              filters: { label: ["production"] },
              organizationId: org,
            })
          ).ok,
        ).toBe(true);

        await everySort(promptListSurface, (options) =>
          prompts.page({ ...options, organizationId: org }),
        );

        await everySort(announcementListSurface, (options) =>
          announcements.page(options),
        );

        await s.as(owner);

        const tags = createTags({
          transport: sqlTransport(s.sql),
          tenant: org,
        });

        const kinds = ["deal", "deal", "task", "task", "task"];

        for (const [index, kind] of kinds.entries()) {
          await tags
            .create({
              kind,
              name: `${index < 2 ? "Holiday" : "Other"} tag ${String(index)}`,
            })
            .orThrow();
        }

        await testBlockList({
          name: "tags",
          target: {
            page: (options) => tags.page(options),
            count: (options) => tags.count(options),
            facets: (options) => tags.facets(options),
            get: (id) => tags.get(id),
          },
          rows: 5,
          sorts: ["name"],
          facets: { kind: { deal: 2, task: 3 } },
          arrayFilter: { column: "kind", values: ["deal", "task"] },
          search: "Holiday",
        });

        await everySort(tagListSurface, (options) => tags.page(options));
        expect((await tags.get(MISSING)).ok).toBe(false);
      } finally {
        await s.close();
      }
    });

    it("pages an empty set of reminders and misses a get", async () => {
      const s = await BlockSession.open(pool);

      try {
        const owner = await s.user("f13-r-owner");
        await s.install(["organizations", "subjects", "reminders"]);
        const org = await s.organization(owner);
        await s.as(owner);

        const reminders = createReminders({
          transport: sqlTransport(s.sql),
          tenant: org,
        });

        await everySort(reminderListSurface, (options) =>
          reminders.page(options),
        );
        expect(hint(await reminders.facets())).toBe("ok");
        expect(hint(await reminders.count())).toBe("ok");
        expect((await reminders.get(MISSING)).ok).toBe(false);
      } finally {
        await s.close();
      }
    });
  },
);
