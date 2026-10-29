import { BuildingIcon, UsersIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadContacts, settle } from "../crm-queries";
import { CreateContactDialog } from "./create-contact-dialog";
import { CrmLoadError } from "./crm-load-error";

/** Render inside `<Suspense>`: the organization's companies and people. */
export async function ContactList() {
  const [t, permissions] = await Promise.all([
    getExtracted("crm"),
    getPermissions(),
  ]);

  if (!can(permissions, "contacts.read")) {
    forbidden();
  }

  const contacts = await settle(loadContacts);

  if (contacts.kind === "no-organization") {
    return null;
  }

  if (contacts.kind === "error") {
    return <CrmLoadError title={t("The contacts didn't load")} />;
  }

  if (contacts.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <UsersIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No contacts yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Add the companies you sell to and the people you talk to.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <CreateContactDialog />
        </EmptyContent>
      </Empty>
    );
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

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Contacts")}</CardTitle>
        <CardDescription>
          {t("{count, plural, one {# contact} other {# contacts}}", {
            count: contacts.data.length,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("Name")}</TableHead>
              <TableHead>{t("Type")}</TableHead>
              <TableHead>{t("Email or domain")}</TableHead>
              <TableHead>{t("Lifecycle")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {contacts.data.map((contact) => (
              <TableRow key={contact.id}>
                <TableCell>
                  <Link
                    href={`/crm/contacts/${contact.id}`}
                    className="flex items-center gap-2 font-medium hover:underline"
                  >
                    {contact.kind === "company" ? (
                      <BuildingIcon
                        className="size-4 text-muted-foreground"
                        aria-hidden
                      />
                    ) : (
                      <UsersIcon
                        className="size-4 text-muted-foreground"
                        aria-hidden
                      />
                    )}
                    {contact.name}
                  </Link>
                </TableCell>
                <TableCell>
                  {contact.kind === "company" ? t("Company") : t("Person")}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {contact.detail ?? ""}
                </TableCell>
                <TableCell>
                  <Badge variant="secondary">
                    {lifecycles.get(contact.lifecycle) ?? contact.lifecycle}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

export function ContactListSkeleton() {
  return <Skeleton className="h-80 rounded-xl" aria-busy="true" />;
}
