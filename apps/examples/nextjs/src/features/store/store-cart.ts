import "server-only";
import { cookies } from "next/headers";

const MAX_LINES = 20;
const MAX_QUANTITY = 20;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** One line of a visitor's cart. */
export interface CartLine {
  readonly variantId: string;
  readonly quantity: number;
}

/**
 * The visitor's cart lives in a cookie per store, `<variantId>:<quantity>`
 * pairs joined by commas. A visitor has no account, so nothing is stored in the
 * database until checkout, and a hand-edited cookie only loses lines.
 */
export const cartCookie = (slug: string): string => `store_cart_${slug}`;

export function parseCart(value: string | undefined): readonly CartLine[] {
  if (value === undefined || value === "") {
    return [];
  }

  const lines: CartLine[] = [];

  for (const part of value.split(",").slice(0, MAX_LINES)) {
    const [variantId, raw] = part.split(":");
    const quantity = Math.trunc(Number(raw));

    if (
      variantId !== undefined &&
      UUID.test(variantId) &&
      Number.isInteger(quantity) &&
      quantity > 0 &&
      !lines.some((line) => line.variantId === variantId)
    ) {
      lines.push({ variantId, quantity: Math.min(quantity, MAX_QUANTITY) });
    }
  }

  return lines;
}

export function serializeCart(lines: readonly CartLine[]): string {
  return lines.map((line) => `${line.variantId}:${line.quantity}`).join(",");
}

export async function readCart(slug: string): Promise<readonly CartLine[]> {
  const store = await cookies();

  return parseCart(store.get(cartCookie(slug))?.value);
}

export const CART_LIMITS = {
  lines: MAX_LINES,
  quantity: MAX_QUANTITY,
} as const;
