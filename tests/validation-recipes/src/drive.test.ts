import { createBlocks, sqlTransport } from "better-supabase/blocks";
import { createRank } from "better-supabase/blocks/rank";
import { createShareLinks } from "better-supabase/blocks/share-links";
import { createTags } from "better-supabase/blocks/tags";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { received, watching, workspace } from "./flow.ts";
import { drive } from "./recipes.ts";
import { dbUrl, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

const DOCUMENT =
  "insert into recipe_drive.documents (organization_id, name) values ($1, 'Q3 plan.pdf') returning id";

describe.skipIf(!live)("drive recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it("shares, labels and files a document, and notifies its watchers", async () => {
    await withRecipe(pool, drive, async (s) => {
      const { owner, member, organizationId, subjectId } = await workspace(
        s,
        "document",
        DOCUMENT,
      );
      const watchers = await watching(s);
      const { shareLinks, tags, rank } = createBlocks(
        { transport: sqlTransport(s.sql) },
        { shareLinks: createShareLinks, tags: createTags, rank: createRank },
      );

      await s.as(owner);
      const link = await shareLinks
        .create(organizationId, "document", subjectId, "viewer")
        .orThrow();
      expect(link.token).not.toBe("");
      const label = await tags
        .create(organizationId, "document", "Finance")
        .orThrow();
      await tags.tag(organizationId, "document", subjectId, label.id).orThrow();
      await rank.move("document", subjectId, { group: "archive" }).orThrow();

      await watchers.relay();
      expect(await received(s, member, subjectId)).toEqual([
        "subject.shared",
        "subject.tagged",
      ]);
      await s.client.query("reset role");
      expect(
        await s.rows(
          "select folder from recipe_drive.documents where id = $1",
          [subjectId],
        ),
      ).toEqual([{ folder: "archive" }]);
    });
  });
});
