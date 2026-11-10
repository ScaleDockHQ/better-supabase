"use client";

import { DownloadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/lib/toast";

interface Probe {
  readonly rows: number;
  readonly limit: number;
}

const noop = (): void => undefined;

const isProbe = (value: unknown): value is Probe =>
  typeof value === "object" &&
  value !== null &&
  "rows" in value &&
  typeof value.rows === "number" &&
  "limit" in value &&
  typeof value.limit === "number";

/**
 * Exports the rows in view. A range up to the route's row limit downloads as a
 * stream; a larger one starts an export job and the requester gets a
 * notification with the download link when it finishes.
 */
export function AuditExportButton({ query }: { query: string }) {
  const t = useExtracted("audit");
  const [pending, setPending] = useState(false);

  const url = (extra: string): string =>
    `/api/audit/export?${[query, extra].filter(Boolean).join("&")}`;

  async function run(): Promise<void> {
    const probe: unknown = await (await fetch(url("probe=1"))).json();

    if (isProbe(probe) && probe.rows <= probe.limit) {
      window.location.assign(url(""));

      return;
    }

    const queued = await fetch(`/api/audit/export-jobs?${query}`, {
      method: "POST",
    });

    if (!queued.ok) {
      throw new Error("The export job was refused");
    }

    toast.success(
      t(
        "The export is running. You get a notification with the download link when it is ready.",
      ),
    );
  }

  function start(): void {
    setPending(true);

    run()
      .catch(() => {
        toast.error(t("The export could not start. Try again."));
      })
      .then(() => {
        setPending(false);
      }, noop);
  }

  return (
    <Button variant="outline" size="sm" disabled={pending} onClick={start}>
      {pending ? <Spinner /> : <DownloadIcon />}
      {t("Export CSV")}
    </Button>
  );
}
