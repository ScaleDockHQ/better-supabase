import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Fact } from "@/features/admin-lists/admin-detail-page";

import { getSecurityStream } from "../security-events-detail";

/** Render inside `<Suspense>`; the fallback is `SecurityEventDetailSkeleton`. */
export async function SecurityEventDetail({ id }: { id: string }) {
  const [stream, t, format] = await Promise.all([
    getSecurityStream(id),
    getExtracted("securityEvents"),
    getFormatter(),
  ]);

  if (stream === "forbidden") {
    forbidden();
  }

  if (!stream) {
    notFound();
  }

  const date = (value: string | null) =>
    value
      ? format.dateTime(new Date(value), {
          dateStyle: "medium",
          timeStyle: "short",
        })
      : "–";

  const delivered = new Set(stream.delivered);

  return (
    <RecordDetailFrame
      title={stream.receiver}
      description={stream.description ?? undefined}
      status={
        <Badge
          variant={stream.status === "enabled" ? "success-light" : "secondary"}
        >
          {stream.status === "enabled"
            ? t("Enabled")
            : stream.status === "paused"
              ? t("Paused")
              : t("Disabled")}
        </Badge>
      }
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Stream")}</CardTitle>
          <CardDescription>
            {t("How this receiver gets security event tokens.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 sm:grid-cols-2">
            <Fact label={t("Delivery")}>
              {stream.delivery === "push" ? t("Push") : t("Poll")}
            </Fact>
            <Fact label={t("Verified")}>{date(stream.verifiedAt)}</Fact>
            <Fact label={t("Audience")}>{stream.audience.join(", ")}</Fact>
            <Fact label={t("Created")}>{date(stream.createdAt)}</Fact>
            {stream.reason ? (
              <Fact label={t("Reason")}>{stream.reason}</Fact>
            ) : null}
          </dl>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Event types")}</CardTitle>
          <CardDescription>
            {t("What the receiver asked for and what the stream delivers.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {stream.requested.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("The receiver requested no event types.")}
            </p>
          ) : (
            <ul className="flex flex-col gap-2">
              {stream.requested.map((event) => (
                <li
                  key={event}
                  className="flex items-center justify-between gap-3 text-sm"
                >
                  <span className="min-w-0 truncate font-mono text-xs">
                    {event}
                  </span>
                  <Badge
                    variant={
                      delivered.has(event) ? "success-light" : "secondary"
                    }
                  >
                    {delivered.has(event) ? t("Delivered") : t("Not delivered")}
                  </Badge>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function SecurityEventDetailSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
