import { EyeIcon, FileCheckIcon, UsersIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";
import { after } from "next/server";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { buttonVariants } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import {
  getAccessLog,
  getClient,
  getClients,
  getConsents,
  logDossierRead,
} from "../care-queries";
import { AccessLogGrid, ClientsGrid, ConsentsGrid } from "./care-grids";
import { CareLoadError } from "./care-load-error";

/** Render inside `<Suspense>`; the fallback is `CareSectionSkeleton`. */
export async function ClientList() {
  const [clients, t] = await Promise.all([getClients(), getExtracted("care")]);

  if (clients.kind === "no-organization") {
    return null;
  }

  if (clients.kind === "error") {
    return <CareLoadError title={t("Clients could not be loaded")} />;
  }

  return clients.data.length === 0 ? (
    <Empty className="border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <UsersIcon />
        </EmptyMedia>
        <EmptyTitle>{t("No clients yet")}</EmptyTitle>
        <EmptyDescription>
          {t(
            "Clients are the customers of your organization. Add one to open their dossier.",
          )}
        </EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Link href="/customers" className={buttonVariants({ size: "sm" })}>
          {t("Add a client")}
        </Link>
      </EmptyContent>
    </Empty>
  ) : (
    <ClientsGrid clients={clients.data} />
  );
}

/**
 * Render inside `<Suspense>`: the client's name and status. A client the caller
 * can't read is a 404. Opening the dossier logs a read of the record.
 */
export async function ClientHeading({ clientId }: { clientId: string }) {
  const [client, t] = await Promise.all([
    getClient(clientId),
    getExtracted("care"),
  ]);

  if (client.kind === "no-organization") {
    return null;
  }

  if (client.kind === "error") {
    return <CareLoadError title={t("This client could not be loaded")} />;
  }

  if (client.data === "missing") {
    notFound();
  }

  after(() => logDossierRead(clientId));

  return (
    <h1 className="text-2xl font-semibold tracking-tight">
      {client.data.name}
    </h1>
  );
}

export function ClientHeadingSkeleton() {
  return <Skeleton className="h-8 w-56" aria-busy="true" />;
}

/** Render inside `<Suspense>`; the fallback is `CareSectionSkeleton`. */
export async function ClientConsents({ clientId }: { clientId: string }) {
  const [consents, t] = await Promise.all([
    getConsents(clientId),
    getExtracted("care"),
  ]);

  if (consents.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Consents")}</FrameTitle>
        <FrameDescription>
          {t(
            "The client's latest decision on each purpose, given by them or a representative.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {consents.kind === "error" ? (
          <CareLoadError title={t("Consents could not be loaded")} />
        ) : consents.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No consents recorded")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Record a decision against a purpose in the consent register.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href="/compliance"
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                {t("Open the consent register")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <ConsentsGrid consents={consents.data} />
        )}
      </FramePanel>
    </Frame>
  );
}

/** Render inside `<Suspense>`; the fallback is `CareSectionSkeleton`. */
export async function ClientAccessLog({ clientId }: { clientId: string }) {
  const [reads, t] = await Promise.all([
    getAccessLog(clientId),
    getExtracted("care"),
  ]);

  if (reads.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Access log")}</FrameTitle>
        <FrameDescription>
          {t(
            "Every read of this client's record, newest first. Repeated reads within a minute count once.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {reads.kind === "error" ? (
          <CareLoadError title={t("The access log could not be loaded")} />
        ) : reads.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <EyeIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No reads logged")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Opening this dossier logs a read; it shows here once it's written.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href="/care"
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                {t("Back to clients")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <AccessLogGrid reads={reads.data} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function CareSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-4 w-72" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-40" />
      </FramePanel>
    </Frame>
  );
}
