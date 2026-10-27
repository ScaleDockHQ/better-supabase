import { formatMoney } from "better-supabase/commerce";
import { ReceiptIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import type { OrderableProduct } from "./create-draft-order-dialog";

import { getOrders, getProducts } from "../shop-queries";
import { CreateDraftOrderDialog } from "./create-draft-order-dialog";
import { OrderStatusBadge } from "./order-status-badge";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: the caller's drafts, then the organization's
 * orders.
 */
export async function OrderList() {
  const permissions = await getPermissions();

  if (!can(permissions, "orders.read")) {
    forbidden();
  }

  const canManage = can(permissions, "orders.manage");

  const [list, products, t, format, locale] = await Promise.all([
    getOrders(),
    canManage && can(permissions, "catalog.read")
      ? getProducts()
      : Promise.resolve(null),
    getExtracted("shop"),
    getFormatter(),
    getLocale(),
  ]);

  if (list.kind === "no-organization") {
    return null;
  }

  const orderable: readonly OrderableProduct[] =
    products?.kind === "ok"
      ? products.data.flatMap((product) =>
          product.status === "active" && product.price
            ? [
                {
                  variantId: product.variantId,
                  label: `${product.title} (${formatMoney(product.price, locale)})`,
                },
              ]
            : [],
        )
      : [];

  const create = canManage ? (
    orderable.length > 0 ? (
      <CreateDraftOrderDialog products={orderable} />
    ) : (
      <Link href="/shop" className={buttonVariants({ size: "sm" })}>
        {t("Add a product first")}
      </Link>
    )
  ) : null;

  const rows =
    list.kind === "ok" ? list.data.drafts.length + list.data.orders.length : 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Orders")}</CardTitle>
        <CardDescription>
          {t("Your draft orders first, then every placed order, newest first.")}
        </CardDescription>
        {rows > 0 ? <CardAction>{create}</CardAction> : null}
      </CardHeader>
      <CardContent>
        {list.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The orders didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : rows === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ReceiptIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No orders yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Start a draft order from a catalog product, then place it.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            {create ? <EmptyContent>{create}</EmptyContent> : null}
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Order")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead>{t("Date")}</TableHead>
                <TableHead className="text-right">{t("Lines")}</TableHead>
                <TableHead className="text-right">{t("Total")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {list.data.drafts.map((draft) => (
                <TableRow key={draft.id}>
                  <TableCell>
                    <Link
                      href={`/shop/orders/${draft.id}`}
                      className="font-medium underline-offset-4 hover:underline"
                    >
                      {t("Draft order")}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <OrderStatusBadge status="draft" />
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {format.dateTime(new Date(draft.createdAt), {
                      dateStyle: "medium",
                    })}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {draft.lines}
                  </TableCell>
                  <TableCell className="text-right text-muted-foreground">
                    {t("Not placed")}
                  </TableCell>
                </TableRow>
              ))}
              {list.data.orders.map((order) => (
                <TableRow key={order.id}>
                  <TableCell>
                    <Link
                      href={`/shop/orders/${order.id}`}
                      className="font-medium underline-offset-4 hover:underline"
                    >
                      {t("Order {number}", { number: order.number })}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <OrderStatusBadge status={order.status} />
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {format.dateTime(new Date(order.placedAt), {
                      dateStyle: "medium",
                    })}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {order.lines}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(order.total, locale)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function OrderListSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
