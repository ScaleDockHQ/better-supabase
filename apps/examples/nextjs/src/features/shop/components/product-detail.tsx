import { formatMoney } from "better-supabase/commerce";
import { TriangleAlertIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ActionButton } from "@/features/sales/components/action-button";
import {
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { setProductStatus } from "../shop-actions";
import { getProducts } from "../shop-queries";

export function ProductDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** One catalog product: price, stock, status and the record sections. */
export async function ProductDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("catalog.read");

  const [t, locale, products, canManage] = await Promise.all([
    getExtracted("shop"),
    getLocale(),
    getProducts(),
    holds("catalog.manage"),
  ]);

  if (products.kind === "no-organization") {
    return null;
  }

  if (products.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The product didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      </Alert>
    );
  }

  const product = products.data.find((candidate) => candidate.id === id);

  if (!product) {
    notFound();
  }

  const subject = { type: "product", id: product.id } as const;

  const facts = [
    { label: t("SKU"), value: product.sku },
    {
      label: t("Price"),
      value: product.price ? formatMoney(product.price, locale) : null,
    },
    {
      label: t("Available"),
      value: product.available === null ? null : String(product.available),
    },
  ];

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "approvals", "reminders"]}
            alongside={tab === "related" ? ["files", "relations"] : []}
          />
        </>
      }
      title={product.title}
      description={product.sku}
      status={
        <Badge
          variant={
            product.status === "active"
              ? "success-light"
              : product.status === "draft"
                ? "secondary"
                : "outline"
          }
        >
          {product.status === "active"
            ? t("Active")
            : product.status === "draft"
              ? t("Draft")
              : t("Archived")}
        </Badge>
      }
      actions={
        canManage ? (
          product.status === "active" ? (
            <ActionButton
              action={setProductStatus}
              input={{ productId: product.id, status: "archived" }}
              label={t("Archive")}
              successMessage={t("Product archived")}
            />
          ) : (
            <ActionButton
              action={setProductStatus}
              input={{ productId: product.id, status: "active" }}
              label={product.status === "draft" ? t("Publish") : t("Restore")}
              successMessage={t("Product active")}
              variant="default"
            />
          )
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/shop/products/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "activity", label: t("Activity") },
          { value: "related", label: t("Related") },
        ]}
      />
      {tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={["files", "relations"]}
          alongside={["tags", "fields", "approvals", "reminders"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>{t("Description")}</CardTitle>
            <CardDescription>
              {t("What the storefront shows for this product.")}
            </CardDescription>
          </CardHeader>
          <CardContent className="text-sm">
            {product.description ?? t("No description yet.")}
          </CardContent>
        </Card>
      )}
    </RecordDetailFrame>
  );
}
