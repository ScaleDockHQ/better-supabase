import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

/**
 * `leave.seeds`: the leave types every organization starts with. Annual leave
 * is tracked and counts down from a yearly allowance; sick and unpaid leave
 * book no ledger entries. An app that adopted its own types table without a
 * `key` column gets none.
 */
export const leaveSeeds: BlockSeeds = {
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    if (!ctx.has("types", "key")) {
      return [];
    }

    const ty = (column: string): string => ctx.col("types", column);

    const allowance = (value: number): Record<string, number> =>
      ctx.has("types", "allowance") ? { [ty("allowance")]: value } : {};

    const kind = (
      key: string,
      name: string,
      flags: { paid: boolean; tracked: boolean },
      extra: Record<string, number>,
    ): { values: Record<string, string | boolean | number> } => ({
      values: {
        [ty("key")]: key,
        [ty("name")]: name,
        [ty("unit")]: "days",
        [ty("paid")]: flags.paid,
        [ty("tracked")]: flags.tracked,
        ...extra,
      },
    });

    return [
      {
        table: ctx.table("types"),
        tenantColumn: ty("tenant"),
        key: [ty("key")],
        rows: [
          kind(
            "annual",
            "Annual leave",
            { paid: true, tracked: true },
            allowance(20),
          ),
          kind("sick", "Sick leave", { paid: true, tracked: false }, {}),
          kind("unpaid", "Unpaid leave", { paid: false, tracked: false }, {}),
        ],
      },
    ];
  },
};
