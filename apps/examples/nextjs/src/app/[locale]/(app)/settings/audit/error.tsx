"use client";

import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";

export default function AuditError({ reset }: { reset: () => void }) {
  const t = useExtracted("audit");

  return (
    <div className="grid justify-items-start gap-2" role="alert">
      <p className="text-sm text-destructive">
        {t("The audit log could not be read.")}
      </p>
      <Button variant="outline" size="sm" onClick={reset}>
        {t("Retry")}
      </Button>
    </div>
  );
}
