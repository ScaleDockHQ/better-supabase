"use client";

import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { retryCustomerRecord } from "../customer-record-actions";

/** A customer page card while its rows load. */
export function RecordCardSkeleton({ rows = 2 }: { rows?: number }) {
  return (
    <Card size="sm">
      <CardHeader>
        <Skeleton className="h-5 w-28" />
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {Array.from({ length: rows }, (_, index) => (
          <Skeleton key={index} className="h-10" />
        ))}
      </CardContent>
    </Card>
  );
}

/** The inline error of a customer page card, with Retry. */
export function RecordLoadError({ title }: { title: string }) {
  const t = useExtracted("customers");

  return (
    <Alert variant="destructive">
      <TriangleAlertIcon />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      <AlertAction>
        <form action={retryCustomerRecord}>
          <Button size="sm" variant="outline" type="submit">
            {t("Retry")}
          </Button>
        </form>
      </AlertAction>
    </Alert>
  );
}
