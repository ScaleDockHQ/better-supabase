import type { OrpcRequestContext } from "better-supabase/orpc";

import { OpenAPIHandler } from "@orpc/openapi/fetch";
import { implement } from "@orpc/server";
import { Hono } from "hono";

import { contract } from "./contract";
import { bsb } from "./router";

const os = implement(contract)
  .$context<OrpcRequestContext>()
  .use(bsb.middleware());

const select = ["id", "name", "status", "organizationId"] as const;

export const contractRouter = os.router({
  customers: {
    list: os.customers.list.handler(({ context, input }) =>
      bsb.unwrap(
        context.db.customers.list({
          select,
          where: input.q ? { name: { contains: input.q } } : {},
          orderBy: { name: "asc" },
          limit: input.limit,
        }),
      ),
    ),
    get: os.customers.get.handler(({ context, input }) =>
      bsb.unwrap(context.db.customers.get(input.id, { select })),
    ),
    create: os.customers.create.handler(({ context, input }) =>
      bsb.unwrap(context.db.customers.create(input, { select })),
    ),
    archive: os.customers.archive
      .use(
        bsb.middleware({
          roles: ["admin"],
          roleClaim: "user_role",
          requireOrganization: true,
        }),
      )
      .handler(({ context, input }) =>
        bsb.unwrap(
          context.db.customers.update(
            input.id,
            { status: "archived" },
            { select },
          ),
        ),
      ),
  },
});

const handle = bsb.fetchHandler(new OpenAPIHandler(contractRouter), {
  prefix: "/api",
});

export const app = new Hono().all("/api/*", (c) => handle(c.req.raw));
