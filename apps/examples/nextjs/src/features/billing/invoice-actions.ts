"use server";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

/** A draft invoice with one line; it gets its number when it's issued. */
export const createDraftInvoice = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      amount: v.pipe(
        v.string(),
        v.trim(),
        v.regex(/^\d+(\.\d{1,2})?$/, "Enter an amount such as 190.00"),
      ),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "invoices.write"),
  },
  async ({ title, amount }, { tenant, db, auth }) => {
    const created = await db.invoices.create(
      tenant,
      { title, currency: SHOP_CURRENCY },
      [
        {
          description: title,
          quantity: 1,
          unitAmount: parseMoney(amount, SHOP_CURRENCY),
        },
      ],
    );

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok(created.data.id);
  },
);

/** Issues a draft: it gets its number, today's date and its due date. */
export const issueInvoice = bsb.action(
  {
    input: v.object({ invoiceId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "invoices.write"),
  },
  async ({ invoiceId }, { db, auth }) => {
    const issued = await db.invoices.issue(invoiceId);

    if (!issued.ok) {
      return issued;
    }

    refreshCaller(auth);

    return ok(issued.data.status);
  },
);
