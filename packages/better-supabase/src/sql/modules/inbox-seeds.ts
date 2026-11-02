import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

/**
 * `inbox.seeds`: the "Help" inbox every organization starts with, on the in-app
 * channel with staff answering. Conversation statuses are a check constraint
 * (`open`, `pending`, `snoozed`, `resolved`), not rows, so there is nothing to
 * seed for them.
 */
export const inboxSeeds: BlockSeeds = {
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    if (!ctx.hasTable("inboxes")) {
      return [];
    }

    const ib = (column: string): string => ctx.col("inboxes", column);

    return [
      {
        table: ctx.table("inboxes"),
        tenantColumn: ib("tenant"),
        key: [ib("name")],
        rows: [
          {
            values: {
              [ib("name")]: "Help",
              [ib("channel")]: "in_app",
              [ib("botMode")]: "human",
            },
          },
        ],
      },
    ];
  },
};
