import type { Money } from "better-supabase/commerce";

import { formatMoney, negateMoney } from "better-supabase/commerce";
import { ShoppingCartIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden, notFound } from "next/navigation";

import { DocumentFlow } from "@/components/record-detail/document-flow";
import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
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
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  requestOrderReturn,
  settleReturn,
} from "@/features/composites/composites-actions";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getOrderDetail } from "../shop-queries";
import { OrderStatusBadge } from "./order-status-badge";
import { OrderTransitions, PlaceOrderButton } from "./order-transitions";
import { PromotionCodeField } from "./promotion-code-field";

// #region recipe:order-detail
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: a placed order, or the caller's draft (an open
 * cart) with the same id, with its lines, totals and next steps.
 */
export async function OrderDetail({ id, tab }: { id: string; tab: string }) {
  const [permissions, detail, t, format, locale] = await Promise.all([
    getPermissions(),
    getOrderDetail(id),
    getExtracted("shop"),
    getFormatter(),
    getLocale(),
  ]);

  if (!can(permissions, "orders.read")) {
    forbidden();
  }

  if (detail.kind === "not-found") {
    notFound();
  }

  if (detail.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="order-detail">
        <TriangleAlertIcon />
        <AlertTitle>{t("The order didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  const view = detail.data;
  const canManage = can(permissions, "orders.manage");
  const amount = (value: Money) => formatMoney(value, locale);

  const problemLabel = (problem: string) => {
    switch (problem) {
      case "shipping_required": {
        return t("Pick a shipping rate first.");
      }

      case "shipping_unavailable": {
        return t("No shipping rate covers this address.");
      }

      case "promotion_unavailable": {
        return t("A promotion code no longer applies.");
      }

      default: {
        return problem;
      }
    }
  };

  const paid =
    view.kind === "order" &&
    (view.status === "paid" || view.status === "fulfilled");

  const shipped =
    view.kind === "order" &&
    view.fulfillments.some(
      (each) => each.status === "shipped" || each.status === "delivered",
    );

  const delivered =
    view.kind === "order" &&
    view.fulfillments.length > 0 &&
    view.fulfillments.every((each) => each.status === "delivered");

  const flow = [
    { label: t("Order"), state: view.kind === "order" ? "done" : "current" },
    {
      label: t("Payment"),
      state: paid ? "done" : view.kind === "order" ? "current" : "todo",
    },
    {
      label: t("Shipment"),
      state: shipped ? "done" : paid ? "current" : "todo",
    },
    {
      label: t("Delivery"),
      state: delivered ? "done" : shipped ? "current" : "todo",
    },
  ] as const;

  const totals: readonly (readonly [string, Money])[] = [
    [t("Subtotal"), view.subtotal],
    ...(view.discountTotal.amount > 0n
      ? [[t("Discount"), negateMoney(view.discountTotal)] as const]
      : []),
    ...(view.shippingTotal.amount > 0n
      ? [[t("Shipping"), view.shippingTotal] as const]
      : []),
    ...(view.kind === "order" && view.taxTotal.amount > 0n
      ? [[t("Tax"), view.taxTotal] as const]
      : []),
  ];

  const subject = { type: "order", id: view.id } as const;
  const placed = view.kind === "order";

  const facts = [
    { label: t("Total"), value: amount(view.total) },
    {
      label: t("Paid"),
      value: view.kind === "order" ? amount(view.paidTotal) : "–",
    },
    { label: t("Lines"), value: String(view.lines.length) },
    {
      label: t("Shipments"),
      value: String(view.kind === "order" ? view.fulfillments.length : 0),
    },
    {
      label: t("Returns"),
      value: String(view.kind === "order" ? view.returns.length : 0),
    },
  ];

  return (
    <div data-recipe="order-detail" className="contents">
      <RecordDetailFrame
        title={
          view.kind === "order"
            ? t("Order {number}", { number: view.number })
            : t("Draft order")
        }
        description={
          view.kind === "order"
            ? t("Placed {date}", {
                date: format.dateTime(new Date(view.placedAt), {
                  dateStyle: "medium",
                  timeStyle: "short",
                }),
              })
            : t("Not placed yet. Prices follow the catalog until you place it.")
        }
        status={
          <OrderStatusBadge
            status={view.kind === "order" ? view.status : "draft"}
          />
        }
        actions={
          placed && canManage && paid ? (
            <ActionDialog
              action={requestOrderReturn}
              title={t("Request a return")}
              description={t("Every unit of the order comes back.")}
              trigger={t("Request return")}
              submitLabel={t("Request return")}
              successMessage={t("Return requested")}
              variant="outline"
              hidden={{ orderId: view.id }}
              fields={[
                {
                  name: "reason",
                  label: t("Reason (optional)"),
                  kind: "textarea",
                },
              ]}
            />
          ) : undefined
        }
        aside={
          <>
            <PropertiesRail title={t("Details")} properties={facts} />
            {placed ? (
              <RecordBoundSections
                subject={subject}
                sections={["tags", "fields", "approvals", "reminders"]}
                alongside={tab === "related" ? ["files", "relations"] : []}
              />
            ) : null}
            <Card>
              <CardHeader>
                <CardTitle>{t("Next step")}</CardTitle>
                <CardDescription>
                  {view.kind === "draft"
                    ? t(
                        "Placing the order reserves its stock and fixes its prices.",
                      )
                    : t(
                        "Without a payments provider, record the payment by hand.",
                      )}
                </CardDescription>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                {view.kind === "draft" && view.problems.length > 0 ? (
                  <Alert variant="warning">
                    <TriangleAlertIcon />
                    <AlertTitle>
                      {t("Check this draft before placing it")}
                    </AlertTitle>
                    <AlertDescription>
                      {view.problems.map(problemLabel).join(" ")}
                    </AlertDescription>
                  </Alert>
                ) : null}
                {canManage ? (
                  view.kind === "draft" ? (
                    <PlaceOrderButton
                      cartId={view.id}
                      disabled={view.lines.length === 0}
                    />
                  ) : (
                    <OrderTransitions
                      orderId={view.id}
                      status={view.status}
                      fulfillments={view.fulfillments}
                    />
                  )
                ) : (
                  <p className="text-sm text-muted-foreground">
                    {t("Ask an admin to move this order along.")}
                  </p>
                )}
                {view.kind === "order" && view.fulfillments.length > 0 ? (
                  <ul className="flex flex-col gap-2">
                    {view.fulfillments.map((fulfillment, index) => (
                      <li
                        key={fulfillment.id}
                        className="flex items-center justify-between gap-2 text-sm"
                      >
                        <span>
                          {t("Shipment {n, number}", { n: index + 1 })}
                        </span>
                        {fulfillment.status === "delivered" ? (
                          <Badge variant="success-light">
                            {t("Delivered")}
                          </Badge>
                        ) : fulfillment.status === "shipped" ? (
                          <Badge variant="info-light">{t("Shipped")}</Badge>
                        ) : fulfillment.status === "cancelled" ? (
                          <Badge variant="destructive-light">
                            {t("Cancelled")}
                          </Badge>
                        ) : (
                          <Badge variant="secondary">{t("Packing")}</Badge>
                        )}
                      </li>
                    ))}
                  </ul>
                ) : null}
              </CardContent>
            </Card>
            <Card>
              <CardHeader>
                <CardTitle>{t("Promotions")}</CardTitle>
              </CardHeader>
              <CardContent>
                {view.kind === "draft" && canManage ? (
                  <PromotionCodeField
                    cartId={view.id}
                    applied={view.promotions.flatMap((promotion) =>
                      promotion.code
                        ? [
                            {
                              code: promotion.code,
                              name: promotion.name,
                              discount: promotion.discount,
                            },
                          ]
                        : [],
                    )}
                    canCreate={can(permissions, "promotions.manage")}
                  />
                ) : view.promotions.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    {t("No promotion was applied.")}
                  </p>
                ) : (
                  <ul className="flex flex-col gap-2">
                    {view.promotions.map((promotion) => (
                      <li
                        key={promotion.code ?? promotion.name}
                        className="flex items-center justify-between gap-2 text-sm"
                      >
                        <span className="flex items-center gap-2">
                          {promotion.code ? (
                            <Badge
                              variant="success-light"
                              className="font-mono"
                            >
                              {promotion.code}
                            </Badge>
                          ) : null}
                          <span className="text-muted-foreground">
                            {promotion.name}
                          </span>
                        </span>
                        <span className="tabular-nums">
                          {amount(negateMoney(promotion.discount))}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          </>
        }
      >
        {placed ? (
          <RecordDetailTabs
            base={`/shop/orders/${view.id}`}
            active={tab}
            tabs={[
              { value: "overview", label: t("Overview") },
              { value: "activity", label: t("Activity") },
              { value: "related", label: t("Related") },
            ]}
          />
        ) : null}
        {placed && tab === "related" ? (
          <RecordBoundSections
            subject={subject}
            sections={["files", "relations"]}
            alongside={["tags", "fields", "approvals", "reminders"]}
          />
        ) : placed && tab === "activity" ? (
          <RecordBoundSections
            subject={subject}
            sections={["discussion", "history"]}
          />
        ) : (
          <>
            <DocumentFlow label={t("Order flow")} steps={flow} />
            <Card>
              <CardHeader>
                <CardTitle>{t("Lines")}</CardTitle>
              </CardHeader>
              <CardContent>
                {view.lines.length === 0 ? (
                  <Empty className="border">
                    <EmptyHeader>
                      <EmptyMedia variant="icon">
                        <ShoppingCartIcon />
                      </EmptyMedia>
                      <EmptyTitle>{t("This draft is empty")}</EmptyTitle>
                      <EmptyDescription>
                        {t("Add a product from the orders page.")}
                      </EmptyDescription>
                    </EmptyHeader>
                  </Empty>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>{t("Product")}</TableHead>
                        <TableHead className="text-right">
                          {t("Quantity")}
                        </TableHead>
                        <TableHead className="text-right">
                          {t("Unit price")}
                        </TableHead>
                        <TableHead className="text-right">
                          {t("Total")}
                        </TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {view.lines.map((line) => (
                        <TableRow key={line.id}>
                          <TableCell>
                            <div className="flex flex-col gap-1">
                              <span className="text-sm">{line.title}</span>
                              <span className="font-mono text-xs text-muted-foreground">
                                {line.sku}
                              </span>
                            </div>
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {line.quantity}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {amount(line.unitAmount)}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {amount(line.total)}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                    <TableFooter>
                      {totals.map(([label, value]) => (
                        <TableRow key={label}>
                          <TableCell
                            colSpan={3}
                            className="text-muted-foreground"
                          >
                            {label}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {amount(value)}
                          </TableCell>
                        </TableRow>
                      ))}
                      <TableRow>
                        <TableCell colSpan={3} className="font-medium">
                          {t("Total")}
                        </TableCell>
                        <TableCell className="text-right font-medium tabular-nums">
                          {amount(view.total)}
                        </TableCell>
                      </TableRow>
                      {view.kind === "order" ? (
                        <TableRow>
                          <TableCell
                            colSpan={3}
                            className="text-muted-foreground"
                          >
                            {t("Paid")}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {amount(view.paidTotal)}
                          </TableCell>
                        </TableRow>
                      ) : null}
                    </TableFooter>
                  </Table>
                )}
              </CardContent>
            </Card>

            {view.kind === "order" && view.returns.length > 0 ? (
              <Card>
                <CardHeader>
                  <CardTitle>{t("Returns")}</CardTitle>
                  <CardDescription>
                    {t("Settle a return as restock, quarantine or reject.")}
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-3">
                  {view.returns.map((each) => (
                    <div
                      key={each.id}
                      className="flex flex-wrap items-center justify-between gap-2 text-sm"
                    >
                      <span className="flex items-center gap-2">
                        <Badge
                          variant={
                            each.status === "requested"
                              ? "warning-light"
                              : each.status === "rejected"
                                ? "destructive-light"
                                : "success-light"
                          }
                        >
                          {each.status}
                        </Badge>
                        <span className="text-muted-foreground">
                          {t("{n, number} units", { n: each.quantity })}
                        </span>
                      </span>
                      {canManage && each.status === "requested" ? (
                        <ActionDialog
                          action={settleReturn}
                          title={t("Settle the return")}
                          trigger={t("Settle")}
                          submitLabel={t("Settle return")}
                          successMessage={t("Return settled")}
                          variant="outline"
                          hidden={{ orderId: view.id, returnId: each.id }}
                          fields={[
                            {
                              name: "disposition",
                              label: t("What happens to the units"),
                              kind: "select",
                              options: [
                                { value: "restock", label: t("Restock") },
                                { value: "quarantine", label: t("Quarantine") },
                                {
                                  value: "reject",
                                  label: t("Reject the return"),
                                },
                              ],
                            },
                            {
                              name: "refund",
                              label: t("Refund the order"),
                              kind: "select",
                              options: [
                                { value: "false", label: t("No refund") },
                                {
                                  value: "true",
                                  label: t("Refund what is paid"),
                                },
                              ],
                            },
                          ]}
                        />
                      ) : null}
                    </div>
                  ))}
                </CardContent>
              </Card>
            ) : null}
          </>
        )}
      </RecordDetailFrame>
    </div>
  );
}
// #endregion recipe:order-detail

export function OrderDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <Skeleton className="h-80 rounded-xl lg:col-span-2" />
      <Skeleton className="h-80 rounded-xl" />
    </div>
  );
}
