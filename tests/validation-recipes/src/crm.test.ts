import { createBlocks, sqlTransport } from "better-supabase/blocks";
import { commentsBlock } from "better-supabase/blocks/comments";
import { rankBlock } from "better-supabase/blocks/rank";
import { tagsBlock } from "better-supabase/blocks/tags";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { received, watching, workspace } from "./flow.ts";
import { crm } from "./recipes.ts";
import { dbUrl, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

const DEAL =
  "insert into recipe_crm.deals (organization_id, name) values ($1, 'Acme renewal') returning id";

describe.skipIf(!live)("CRM recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("notifies a deal's watchers about comments, tags and stage moves, except the actor", async () => {
    await withRecipe(pool, crm, async (s) => {
      const { owner, member, organizationId, subjectId } = await workspace(
        s,
        "deal",
        DEAL,
      );

      await s.watch(owner, organizationId, "deal", subjectId);
      const watchers = await watching(s);

      const { comments, tags, rank } = createBlocks(
        { transport: sqlTransport(s.sql), tenant: organizationId },
        { comments: commentsBlock, tags: tagsBlock, rank: rankBlock },
      );

      await s.as(owner);
      const deal = { type: "deal", id: subjectId };
      await comments.create(deal, { body: "Sent the renewal quote" }).orThrow();
      const hot = await tags.create("deal", "Hot").orThrow();
      await tags.tag(deal, hot.id).orThrow();
      await rank.move("deal", subjectId, { group: "qualified" }).orThrow();

      expect(await watchers.relay()).toBeGreaterThanOrEqual(3);
      expect(await received(s, member, subjectId)).toEqual([
        "comment.posted",
        "subject.moved",
        "subject.tagged",
      ]);
      expect(await received(s, owner, subjectId)).toEqual([]);
    });
  });

  it("refuses a stage move the pipeline does not allow", async () => {
    await withRecipe(pool, crm, async (s) => {
      const { owner, subjectId } = await workspace(s, "deal", DEAL);
      await s.as(owner);
      expect(
        await s.hint("better_supabase.move('deal', $1, null, null, 'won')", [
          subjectId,
        ]),
      ).toBe("STATE_TRANSITION_INVALID");
    });
  });
});
