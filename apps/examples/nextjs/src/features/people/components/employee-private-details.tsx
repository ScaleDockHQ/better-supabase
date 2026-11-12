"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { EyeIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

import { getPrivateDetails } from "../people-actions";

/**
 * The private details of one employee. They read on request, because each read
 * is audited, so opening the page alone reveals nothing.
 */
export function EmployeePrivateDetails({ employeeId }: { employeeId: string }) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();
  const read = useAction(getPrivateDetails);

  if (read.pending) {
    return <Skeleton className="h-24" aria-busy="true" />;
  }

  if (read.error) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The private details didn't load")}</AlertTitle>
        <AlertDescription>{errorMessage(read.error)}</AlertDescription>
        <AlertAction>
          <Button
            size="sm"
            variant="outline"
            onClick={() => void read.run({ employeeId })}
          >
            {t("Retry")}
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  if (read.data === undefined) {
    return (
      <Button
        variant="outline"
        size="sm"
        className="w-fit"
        onClick={() => void read.run({ employeeId })}
      >
        <EyeIcon />
        {t("Reveal private details")}
      </Button>
    );
  }

  const rows = [
    { label: t("Phone"), value: read.data?.phone },
    { label: t("Personal email"), value: read.data?.personalEmail },
    { label: t("Birth date"), value: read.data?.birthDate },
  ];

  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
      {rows.map((row) => (
        <div key={row.label} className="contents">
          <dt className="text-muted-foreground">{row.label}</dt>
          <dd>{row.value ?? t("Not set")}</dd>
        </div>
      ))}
    </dl>
  );
}
