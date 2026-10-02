import { os } from "@orpc/server";
import { createOrpc, type OrpcRequestContext } from "better-supabase/orpc";
import * as v from "valibot";

import { sb } from "./lib/supabase";

export const bs = createOrpc(sb);

const base = os.$context<OrpcRequestContext>();
const authed = base.use(bs.middleware());

const customer = ["id", "name", "status", "organizationId"] as const;

export const router = {
  me: authed.handler(({ context }) => ({ kind: context.auth.kind })),
  customers: {
    list: authed
      .input(
        v.object({
          q: v.optional(v.string()),
          limit: v.optional(
            v.pipe(v.number(), v.integer(), v.maxValue(100)),
            20,
          ),
        }),
      )
      .handler(({ context, input }) =>
        bs.unwrap(
          context.db.customers.findMany({
            select: customer,
            where: input.q ? { name: { ilike: `%${input.q}%` } } : {},
            orderBy: { name: "asc" },
            limit: input.limit,
          }),
        ),
      ),
    get: authed
      .input(v.object({ id: v.pipe(v.string(), v.uuid()) }))
      .handler(({ context, input }) =>
        bs.unwrap(
          context.db.customers.findById(input.id, { select: customer }),
        ),
      ),
    create: authed
      .input(
        v.object({
          name: v.pipe(v.string(), v.minLength(1)),
          organizationId: v.pipe(v.string(), v.uuid()),
        }),
      )
      .handler(({ context, input }) =>
        bs.unwrap(context.db.customers.create(input, { select: customer })),
      ),
    remove: authed
      .input(v.object({ id: v.pipe(v.string(), v.uuid()) }))
      .handler(async ({ context, input }) => {
        await bs.unwrap(context.db.customers.delete(input.id));
        return { deleted: true };
      }),
  },
};
