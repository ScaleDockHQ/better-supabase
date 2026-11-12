import { ShoppingCartIcon, StoreIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";

import { readCart } from "../store-cart";

/** The store's own header: a link to the catalog and the cart with its count. */
export async function StoreNav({ slug }: { slug: string }) {
  const [t, lines] = await Promise.all([getExtracted("store"), readCart(slug)]);
  const count = lines.reduce((sum, line) => sum + line.quantity, 0);

  return (
    <nav
      aria-label={t("Store")}
      className="flex items-center justify-between gap-2"
    >
      <Link
        href={`/store/${slug}`}
        className={buttonVariants({ variant: "ghost", size: "sm" })}
      >
        <StoreIcon />
        {t("Store")}
      </Link>
      <Link
        href={`/store/${slug}/cart`}
        className={buttonVariants({ variant: "outline", size: "sm" })}
      >
        <ShoppingCartIcon />
        {t("Cart")}
        <span className="tabular-nums">{count}</span>
      </Link>
    </nav>
  );
}

export function StoreNavSkeleton() {
  return <div className="h-8" aria-hidden="true" />;
}
