import type { Catalog, ProductInput } from "./catalog.ts";

import { AsyncResult } from "../../core/result.ts";

/**
 * The multi-step helpers of the catalog client. They call `client()`, the
 * hooked client, so app hooks see each step.
 */
export function catalogHelpers<F extends object>(
  client: () => Catalog<F>,
): Pick<Catalog<F>, "createSimpleProduct"> {
  return {
    createSimpleProduct: ({
      organizationId,
      title,
      price,
      sku,
      slug,
      description,
      publish,
    }) =>
      client()
        .createProduct({
          organizationId,
          // SAFETY: the product input's own keys; no extra columns are set.
          input: {
            title,
            ...(slug === undefined ? {} : { slug }),
            ...(description === undefined ? {} : { description }),
          } as ProductInput & Partial<F>,
        })
        .andThen((product) =>
          client()
            .createVariant({
              productId: product.id,
              input: sku === undefined ? {} : { sku },
            })
            .andThen((variant) =>
              client()
                .setPrice({ variantId: variant.id, input: { amount: price } })
                .andThen((saved) =>
                  publish
                    ? client()
                        .setProductStatus({
                          productId: product.id,
                          status: "active",
                        })
                        .map(() => ({
                          product: { ...product, status: "active" as const },
                          variant,
                          price: saved,
                        }))
                    : AsyncResult.ok({ product, variant, price: saved }),
                ),
            ),
        ),
  };
}
