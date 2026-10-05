import { oc } from "@orpc/contract";
import { openapi } from "@orpc/openapi";
import * as v from "valibot";

const id = v.pipe(v.string(), v.uuid());

const customer = v.object({
  id,
  name: v.string(),
  status: v.string(),
  organizationId: id,
});

export const contract = {
  customers: {
    list: oc
      .meta(openapi({ method: "GET", path: "/customers" }))
      .input(
        v.object({
          q: v.optional(v.string()),
          limit: v.optional(
            v.pipe(
              v.unknown(),
              v.transform(Number),
              v.number(),
              v.integer(),
              v.maxValue(100),
            ),
            20,
          ),
        }),
      )
      .output(v.array(customer)),
    get: oc
      .meta(openapi({ method: "GET", path: "/customers/{id}" }))
      .input(v.object({ id }))
      .output(customer),
    create: oc
      .meta(openapi({ method: "POST", path: "/customers", successStatus: 201 }))
      .input(
        v.object({
          name: v.pipe(v.string(), v.minLength(1)),
          organizationId: id,
        }),
      )
      .output(customer),
  },
};
