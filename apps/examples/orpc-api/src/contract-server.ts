import type { OrpcRequestContext } from "better-supabase/orpc";

import { OpenAPIHandler } from "@orpc/openapi/fetch";
import { implement } from "@orpc/server";
import { Hono } from "hono";

import { contract } from "./contract";
import { bs } from "./router";

const os = implement(contract)
  .$context<OrpcRequestContext>()
  .use(bs.middleware());

const select = ["id", "name", "status", "organizationId"] as const;

export const contractRouter = os.router({
  customers: {
    list: os.customers.list.handler(({ context, input }) =>
      bs.unwrap(
        context.db.customers.findMany({
          select,
          where: input.q ? { name: { contains: input.q } } : {},
          orderBy: { name: "asc" },
          limit: input.limit,
        }),
      ),
    ),
    get: os.customers.get.handler(({ context, input }) =>
      bs.unwrap(context.db.customers.findById(input.id, { select })),
    ),
    create: os.customers.create.handler(({ context, input }) =>
      bs.unwrap(context.db.customers.create(input, { select })),
    ),
  },
});

const handle = bs.fetchHandler(new OpenAPIHandler(contractRouter), {
  prefix: "/api",
});

export const app = new Hono().all("/api/*", (c) => handle(c.req.raw));
