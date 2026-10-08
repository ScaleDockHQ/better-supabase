import { createOrpc } from "better-supabase/orpc";
import * as v from "valibot";

import { betterSupabase } from "./lib/supabase";

export const bs = createOrpc(betterSupabase);

const authed = bs.authed();

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const admin = bs.authed({
  roles: ["admin"],
  roleClaim: "user_role",
  requireTenant: true,
});

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
            where: input.q ? { name: { contains: input.q } } : {},
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
    archive: admin
      .input(v.object({ id: v.pipe(v.string(), v.uuid()) }))
      .handler(({ context, input }) =>
        bs.unwrap(
          context.db.customers.update(
            input.id,
            { status: "archived" },
            { select: customer },
          ),
        ),
      ),
    remove: authed
      .input(v.object({ id: v.pipe(v.string(), v.uuid()) }))
      .handler(async ({ context, input }) => {
        await bs.unwrap(context.db.customers.delete(input.id));
        return { deleted: true };
      }),
  },
};
