import { os } from "@orpc/server";
import { createOrpc, type OrpcRequestContext } from "better-supabase/orpc";
import { z } from "zod";

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
        z.object({
          q: z.string().optional(),
          limit: z.number().int().max(100).default(20),
        }),
      )
      .handler(({ context, input }) =>
        bs.unwrap(
          context.db.customers.findMany({
            select: customer,
            ...(input.q ? { where: { name: { ilike: `%${input.q}%` } } } : {}),
            orderBy: { name: "asc" },
            limit: input.limit,
          }),
        ),
      ),
    get: authed
      .input(z.object({ id: z.uuid() }))
      .handler(({ context, input }) =>
        bs.unwrap(
          context.db.customers.findById(input.id, { select: customer }),
        ),
      ),
    create: authed
      .input(z.object({ name: z.string().min(1), organizationId: z.uuid() }))
      .handler(({ context, input }) =>
        bs.unwrap(context.db.customers.create(input, { select: customer })),
      ),
    remove: authed
      .input(z.object({ id: z.uuid() }))
      .handler(async ({ context, input }) => {
        await bs.unwrap(context.db.customers.delete(input.id));
        return { deleted: true };
      }),
  },
};
