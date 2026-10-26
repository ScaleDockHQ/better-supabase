import { Link2OffIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { getSharedCustomer } from "../shared-customer-queries";
import { CustomerStatus } from "./customer-status";

/** Render inside `<Suspense>`: reads the `token` param. */
export async function SharedCustomerCard({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;

  const [customer, t, format] = await Promise.all([
    getSharedCustomer(token),
    getExtracted("customers"),
    getFormatter(),
  ]);

  if (!customer) {
    return (
      <Card data-testid="shared-customer-missing">
        <CardHeader className="text-center">
          <Link2OffIcon className="mx-auto size-8 text-muted-foreground" />
          <CardTitle>{t("This link doesn't work")}</CardTitle>
          <CardDescription>
            {t("It expired, was revoked or never existed.")}
          </CardDescription>
        </CardHeader>
        <CardFooter>
          <Link
            href="/login"
            className={buttonVariants({ className: "w-full" })}
          >
            {t("Sign in")}
          </Link>
        </CardFooter>
      </Card>
    );
  }

  return (
    <Card data-testid="shared-customer">
      <CardHeader>
        <div className="flex items-center gap-2">
          <CardTitle>{customer.name}</CardTitle>
          <CustomerStatus status={customer.status} />
        </div>
        <CardDescription>
          {customer.expiresAt
            ? t("Shared with you until {date}.", {
                date: format.dateTime(new Date(customer.expiresAt), {
                  dateStyle: "long",
                }),
              })
            : t("Shared with you.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="text-sm text-muted-foreground">
        {t("This is a read-only view. Sign in to see the full record.")}
      </CardContent>
    </Card>
  );
}

export function SharedCustomerCardSkeleton() {
  return (
    <Card>
      <CardHeader className="flex flex-col gap-2">
        <Skeleton className="h-6 w-40" />
        <Skeleton className="h-4 w-56" />
      </CardHeader>
      <CardContent>
        <Skeleton className="h-4 w-full" />
      </CardContent>
    </Card>
  );
}
