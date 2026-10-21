import "server-only";
import { DbException, type Result } from "better-supabase";
import { type RpcClient, rpcTransport } from "better-supabase/blocks";
import {
  createTemplates,
  defineTemplateType,
  type Templates,
} from "better-supabase/blocks/templates";
import * as v from "valibot";

import { blockConfig } from "@/lib/supabase/blocks.generated";

/** The body of a customer template: the fields a new customer starts with. */
const ApplyValues = v.object({
  name: v.pipe(v.string(), v.trim(), v.minLength(1)),
});

export const CustomerTemplateBody = v.object({
  status: v.picklist(["lead", "active"]),
});

export type CustomerTemplateBody = v.InferOutput<typeof CustomerTemplateBody>;

interface NewCustomer {
  readonly name: string;
  readonly organizationId: string;
  readonly status: CustomerTemplateBody["status"];
}

const transportOf = (supabase: RpcClient) =>
  rpcTransport(supabase, { schema: blockConfig.templates.api });

/** The templates block for reads and writes; `apply` needs `customerTemplates`. */
export function templatesOf(supabase: RpcClient): Templates {
  return createTemplates({ transport: transportOf(supabase) });
}

/**
 * The templates block with a `customer` type. Applying one creates a customer
 * named by the `name` value, through `createCustomer`.
 */
export function customerTemplates(
  supabase: RpcClient,
  createCustomer: (
    row: NewCustomer,
  ) => PromiseLike<Result<{ readonly id: string }>>,
): Templates {
  return createTemplates({
    transport: transportOf(supabase),
    types: {
      customer: defineTemplateType({
        body: CustomerTemplateBody,
        apply: async ({ body, organizationId, values }) => {
          const { name } = v.parse(ApplyValues, values);

          const created = await createCustomer({
            name,
            organizationId,
            status: body.status,
          });

          if (!created.ok) {
            throw new DbException(created.error);
          }

          return { subject: { type: "customer", id: created.data.id } };
        },
      }),
    },
  });
}
