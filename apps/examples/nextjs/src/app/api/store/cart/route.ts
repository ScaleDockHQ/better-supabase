import type { NextRequest } from "next/server";

import { NextResponse } from "next/server";
import * as v from "valibot";

import {
  CART_LIMITS,
  cartCookie,
  parseCart,
  serializeCart,
} from "@/features/store/store-cart";

const Slug = v.pipe(v.string(), v.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/));
const Id = v.pipe(v.string(), v.uuid());

const Form = v.variant("intent", [
  v.object({ intent: v.literal("add"), slug: Slug, variantId: Id }),
  v.object({
    intent: v.literal("set"),
    slug: Slug,
    variantId: Id,
    quantity: v.pipe(
      v.string(),
      v.transform(Number),
      v.integer(),
      v.minValue(0),
      v.maxValue(CART_LIMITS.quantity),
    ),
  }),
]);

const COOKIE_MAX_AGE = 60 * 60 * 24 * 14;

/** Where the visitor goes back to: the page that posted, else the cart. */
function backTo(request: NextRequest, slug: string): URL {
  const fallback = new URL(`/store/${slug}/cart`, request.url);
  const referer = request.headers.get("referer");

  if (referer === null) {
    return fallback;
  }

  const target = new URL(referer);

  return target.origin === fallback.origin ? target : fallback;
}

/**
 * `POST /api/store/cart`: changes the visitor's cart cookie and sends them back
 * to the page they came from. A visitor has no account, so the cart is the
 * cookie and the form works without JavaScript.
 */
export async function POST(request: NextRequest) {
  const parsed = v.safeParse(
    Form,
    Object.fromEntries(await request.formData()),
  );

  if (!parsed.success) {
    return new Response(null, { status: 400 });
  }

  const { slug, variantId } = parsed.output;
  const name = cartCookie(slug);

  const lines = parseCart(request.cookies.get(name)?.value);

  const next =
    parsed.output.intent === "add"
      ? [
          ...lines.filter((line) => line.variantId !== variantId),
          {
            variantId,
            quantity: Math.min(
              (lines.find((line) => line.variantId === variantId)?.quantity ??
                0) + 1,
              CART_LIMITS.quantity,
            ),
          },
        ].slice(0, CART_LIMITS.lines)
      : lines.flatMap((line) => {
          if (line.variantId !== variantId) {
            return [line];
          }

          return parsed.output.intent === "set" && parsed.output.quantity > 0
            ? [{ ...line, quantity: parsed.output.quantity }]
            : [];
        });

  const response = NextResponse.redirect(backTo(request, slug), 303);

  response.cookies.set(name, serializeCart(next), {
    path: "/",
    maxAge: next.length === 0 ? 0 : COOKIE_MAX_AGE,
    sameSite: "lax",
    httpOnly: true,
  });

  return response;
}
