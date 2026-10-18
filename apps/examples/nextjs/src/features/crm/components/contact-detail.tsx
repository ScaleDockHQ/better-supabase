import { BuildingIcon, UserPlusIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";
import { Suspense } from "react";

import { Badge } from "@/components/reui/badge";
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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { loadContact, settle } from "../crm-queries";
import {
  ActivityTimeline,
  ActivityTimelineSkeleton,
} from "./activity-timeline";
import { CreateContactDialog } from "./create-contact-dialog";
import { CrmLoadError } from "./crm-load-error";
import { LinkPersonForm } from "./link-person-form";

// #region recipe:contact-detail
/**
 * Render inside `<Suspense>`: a company or a person with its details, its
 * people (for a company) and the activity timeline.
 */
export async function ContactDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const [{ id }, session, t] = await Promise.all([
    params,
    getSession(),
    getExtracted("crm"),
  ]);

  if (!can(session, "parties.read")) {
    forbidden();
  }

  const loaded = await settle(() => loadContact(id));

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The contact didn't load")} />;
  }

  const contact = loaded.data;

  if (!contact) {
    notFound();
  }

  const lifecycles = new Map([
    ["lead", t("Lead")],
    ["prospect", t("Prospect")],
    ["customer", t("Customer")],
    ["churned", t("Churned")],
    ["mql", t("Marketing qualified")],
    ["sql", t("Sales qualified")],
    ["opportunity", t("Opportunity")],
  ]);

  const details = [
    { label: t("Email"), value: contact.email },
    { label: t("Phone"), value: contact.phone },
    { label: t("Title"), value: contact.title },
    { label: t("Domain"), value: contact.domain },
    { label: t("Website"), value: contact.website },
  ].filter((detail) => detail.value !== null);

  return (
    <div data-recipe="contact-detail" className="grid gap-6 lg:grid-cols-3">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Card>
          <CardHeader>
            <CardTitle>{contact.name}</CardTitle>
            <CardDescription className="flex items-center gap-2">
              <Badge variant="outline">
                {contact.kind === "company" ? t("Company") : t("Person")}
              </Badge>
              <Badge variant="primary-light">
                {lifecycles.get(contact.lifecycle) ?? contact.lifecycle}
              </Badge>
            </CardDescription>
          </CardHeader>
          <CardContent>
            {details.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t("No details yet.")}
              </p>
            ) : (
              <dl className="grid gap-3 sm:grid-cols-2">
                {details.map((detail) => (
                  <div key={detail.label} className="flex flex-col gap-0.5">
                    <dt className="text-xs text-muted-foreground">
                      {detail.label}
                    </dt>
                    <dd className="text-sm">{detail.value}</dd>
                  </div>
                ))}
              </dl>
            )}
          </CardContent>
        </Card>
        <Suspense fallback={<ActivityTimelineSkeleton />}>
          <ActivityTimeline subject={{ type: contact.kind, id: contact.id }} />
        </Suspense>
      </div>
      {contact.kind === "company" ? (
        <Card>
          <CardHeader>
            <CardTitle>{t("People")}</CardTitle>
            <CardDescription>
              {t("The people you talk to at {name}.", { name: contact.name })}
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            {contact.people.length === 0 ? (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <UserPlusIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No people yet")}</EmptyTitle>
                  <EmptyDescription>
                    {contact.candidates.length === 0
                      ? t("Add a person first, then link them here.")
                      : t("Link a person below.")}
                  </EmptyDescription>
                </EmptyHeader>
                {contact.candidates.length === 0 ? (
                  <EmptyContent>
                    <CreateContactDialog variant="outline" />
                  </EmptyContent>
                ) : null}
              </Empty>
            ) : (
              <ul className="flex flex-col divide-y">
                {contact.people.map((person) => (
                  <li
                    key={person.id}
                    className="flex items-center justify-between gap-3 py-3 first:pt-0 last:pb-0"
                  >
                    <div className="flex min-w-0 flex-col gap-0.5">
                      <Link
                        href={`/crm/contacts/${person.id}`}
                        className="truncate text-sm font-medium hover:underline"
                      >
                        {person.name}
                      </Link>
                      <span className="truncate text-xs text-muted-foreground">
                        {[person.role ?? person.title, person.email]
                          .filter((part) => part !== null)
                          .join(" · ")}
                      </span>
                    </div>
                    {person.primary ? (
                      <Badge variant="success-light">{t("Primary")}</Badge>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
            {can(session, "parties.write") ? (
              <LinkPersonForm
                companyId={contact.id}
                people={contact.candidates.map((person) => ({
                  value: person.id,
                  label: person.name,
                }))}
              />
            ) : null}
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>{t("Companies")}</CardTitle>
            <CardDescription>
              {t("Link this person from a company's page.")}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link
              href="/crm/contacts"
              className="flex items-center gap-2 text-sm font-medium hover:underline"
            >
              <BuildingIcon className="size-4" aria-hidden />
              {t("All contacts")}
            </Link>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
// #endregion recipe:contact-detail

export function ContactDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-40 rounded-xl" />
        <ActivityTimelineSkeleton />
      </div>
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}
