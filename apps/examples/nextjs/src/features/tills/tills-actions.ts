"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { planCashAccount } from "./cash-account";

/**
 * Adds a euro till whose cash sits in the accounting chart, so the closing
 * count books its variance. The till maps an unused asset account named for
 * cash when the chart has one and otherwise creates a new one (see
 * `planCashAccount`).
 */
export const createTill = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.minLength(1), v.maxLength(100)),
    }),
    requireTenant: true,
    permission: "tills.manage",
  },
  async ({ name }, { tenant: organizationId, db }) => {
    const settings = await db.accounting.settings(organizationId);

    if (!settings.ok) {
      return settings;
    }

    if (settings.data === undefined) {
      const setup = await db.accounting.setup({ organizationId });

      if (!setup.ok) {
        return setup;
      }
    }

    const [accounts, tills] = await Promise.all([
      db.accounting.accounts({ organizationId }),
      db.tills.listTills({ includeArchived: true }),
    ]);

    if (!accounts.ok) {
      return accounts;
    }

    if (!tills.ok) {
      return tills;
    }

    const plan = planCashAccount(
      accounts.data,
      new Set(tills.data.flatMap((till) => till.accountId ?? [])),
      name,
    );

    let accountId: string;

    if (plan.kind === "map") {
      accountId = plan.accountId;
    } else {
      const created = await db.accounting.saveAccount({
        organizationId,
        input: {
          code: plan.code,
          name: plan.name,
          type: "asset",
          currency: "EUR",
        },
      });

      if (!created.ok) {
        return created;
      }

      accountId = created.data.id;
    }

    const till = await db.tills.createTill({
      name,
      currency: "EUR",
      accountId,
    });

    return till.ok ? ok({ id: till.data.id, accountId }) : till;
  },
);
