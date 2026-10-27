"use client";

import { useAction } from "better-supabase/react";
import { PlugIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useSearchParams } from "next/navigation";
import { useTransition } from "react";
import { toast } from "sonner";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
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
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type {
  IntegrationRow,
  IntegrationsRead,
  IntegrationStatus,
} from "../integration-queries";

import {
  connectIntegration,
  disconnectIntegration,
} from "../integration-actions";

const DOCS_URL = "https://vercel.com/docs/connect";

function StatusBadge({ status }: { status: IntegrationStatus }) {
  const t = useExtracted("integrations");

  switch (status) {
    case "connected": {
      return <Badge variant="success-light">{t("Connected")}</Badge>;
    }

    case "available": {
      return <Badge variant="secondary">{t("Not connected")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

function ConnectButton({ row }: { row: IntegrationRow }) {
  const t = useExtracted("integrations");
  const errorMessage = useErrorMessage();

  const connect = useAction(connectIntegration, {
    onSuccess: (url) => {
      window.location.assign(url);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      type="button"
      size="sm"
      variant="outline"
      disabled={connect.pending}
      onClick={() => {
        void connect.run({ id: row.id });
      }}
    >
      {t("Connect")}
    </Button>
  );
}

function DisconnectButton({ row }: { row: IntegrationRow }) {
  const t = useExtracted("integrations");
  const errorMessage = useErrorMessage();

  const disconnect = useAction(disconnectIntegration, {
    onSuccess: () => {
      toast.success(t("{name} disconnected", { name: row.name }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={<Button type="button" size="sm" variant="ghost" />}
      >
        {t("Disconnect")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            {t("Disconnect {name}?", { name: row.name })}
          </AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "The app loses access to your account until you connect it again. Mail sync for it stops.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={disconnect.pending}>
            {t("Cancel")}
          </AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={disconnect.pending}
            onClick={() => {
              void disconnect.run({ id: row.id });
            }}
          >
            {t("Disconnect")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function IntegrationRows({ rows }: { rows: readonly IntegrationRow[] }) {
  const t = useExtracted("integrations");

  return (
    <Table data-testid="integrations">
      <TableHeader>
        <TableRow>
          <TableHead>{t("Account")}</TableHead>
          <TableHead>{t("Status")}</TableHead>
          <TableHead>
            <span className="sr-only">{t("Actions")}</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((row) => (
          <TableRow key={row.id}>
            <TableCell className="font-medium">{row.name}</TableCell>
            <TableCell>
              <StatusBadge status={row.status} />
            </TableCell>
            <TableCell className="text-right">
              {row.status === "connected" ? (
                <DisconnectButton row={row} />
              ) : (
                <ConnectButton row={row} />
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

/** The outcome the Connect callback route put in the query, if any. */
function CallbackOutcome({ rows }: { rows: readonly IntegrationRow[] }) {
  const t = useExtracted("integrations");
  const params = useSearchParams();

  const nameOf = (id: string | null) =>
    rows.find((row) => row.id === id)?.name ?? id ?? "";

  if (params.has("connected")) {
    return (
      <Alert variant="success">
        <AlertTitle>
          {t("{name} is connected", { name: nameOf(params.get("connected")) })}
        </AlertTitle>
      </Alert>
    );
  }

  if (params.has("failed")) {
    return (
      <Alert variant="destructive">
        <AlertTitle>
          {t("{name} didn't connect", { name: nameOf(params.get("failed")) })}
        </AlertTitle>
        <AlertDescription>
          {t("Consent was declined or expired. Try connecting again.")}
        </AlertDescription>
      </Alert>
    );
  }

  return null;
}

/**
 * The signed-in user's own accounts at third parties, granted through Vercel
 * Connect. The grant lives at Connect, not in this database; the app only asks
 * Connect for a token as the user.
 */
export function IntegrationSettings({ read }: { read: IntegrationsRead }) {
  const t = useExtracted("integrations");
  const errorMessage = useErrorMessage();
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  return (
    <Card data-testid="integration-settings">
      <CardHeader>
        <CardTitle>{t("Integrations")}</CardTitle>
        <CardDescription>
          {t(
            "Your own accounts the app may use on your behalf, such as the mailbox mail sync reads.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {read.ok ? (
          <>
            <CallbackOutcome rows={read.rows} />
            {read.rows.length === 0 ? (
              <Empty className="border" data-testid="integrations-empty">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <PlugIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No integrations set up")}</EmptyTitle>
                  <EmptyDescription>
                    {t(
                      "Add a Vercel Connect connector and set its UID in the environment to list it here.",
                    )}
                  </EmptyDescription>
                </EmptyHeader>
                <EmptyContent>
                  <a
                    href={DOCS_URL}
                    target="_blank"
                    rel="noreferrer"
                    className={buttonVariants({
                      variant: "outline",
                      size: "sm",
                    })}
                  >
                    {t("Read the Connect docs")}
                  </a>
                </EmptyContent>
              </Empty>
            ) : (
              <IntegrationRows rows={read.rows} />
            )}
          </>
        ) : (
          <Alert variant="destructive">
            <AlertTitle>{t("The integrations didn't load")}</AlertTitle>
            <AlertDescription>{errorMessage(read.error)}</AlertDescription>
            <AlertAction>
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={retrying}
                onClick={() => {
                  startRetry(() => {
                    router.refresh();
                  });
                }}
              >
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        )}
      </CardContent>
    </Card>
  );
}

const SKELETON_ROWS = ["first", "second"];

/** Keeps the card's title in the static shell, so the tab commits it at once. */
export function IntegrationSettingsSkeleton() {
  const t = useExtracted("integrations");

  return (
    <Card aria-busy="true">
      <CardHeader>
        <CardTitle>{t("Integrations")}</CardTitle>
        <CardDescription>
          {t(
            "Your own accounts the app may use on your behalf, such as the mailbox mail sync reads.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {SKELETON_ROWS.map((row) => (
          <Skeleton key={row} className="h-11 w-full" />
        ))}
      </CardContent>
    </Card>
  );
}
