import { getExtracted, getFormatter } from "next-intl/server";
import Image from "next/image";
import { notFound } from "next/navigation";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembers } from "@/features/organization/organization-queries";
import { activeOrganizationId, can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { initials } from "@/lib/initials";

import { getCustomer, getCustomerComments } from "../customer-queries";
import { CommentForm } from "./comment-form";
import { CustomerLogoForm } from "./customer-logo-form";
import { CustomerStatus } from "./customer-status";

/** Render inside `<Suspense>`: reads the `id` param and the session. */
export async function CustomerDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const [{ id }, session] = await Promise.all([params, getSession()]);
  const organizationId = activeOrganizationId(session);
  if (!organizationId) notFound();
  const [customer, comments, members, t, format] = await Promise.all([
    getCustomer(id),
    getCustomerComments(organizationId, id),
    getMembers(organizationId),
    getExtracted("customers"),
    getFormatter(),
  ]);
  if (!customer) notFound();
  const names = new Map(
    members.map((member) => [member.userId, member.name ?? member.email]),
  );
  return (
    <div className="grid gap-6 lg:grid-cols-3">
      <div className="space-y-6 lg:col-span-2">
        <div className="flex items-center gap-4">
          {customer.logoUrl ? (
            <Image
              src={customer.logoUrl}
              width={56}
              height={56}
              alt=""
              className="rounded-xl"
            />
          ) : (
            <span className="bg-muted text-muted-foreground flex size-14 items-center justify-center rounded-xl text-lg font-semibold">
              {initials(customer.name, null)}
            </span>
          )}
          <div className="space-y-1">
            <h1 className="text-2xl font-semibold tracking-tight">
              {customer.name}
            </h1>
            <p className="text-muted-foreground text-sm">
              {t("Customer since {date}", {
                date: format.dateTime(new Date(customer.createdAt), {
                  dateStyle: "long",
                }),
              })}
            </p>
          </div>
          <CustomerStatus status={customer.status} />
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{t("Comments")}</CardTitle>
            <CardDescription>
              {t("Visible to everyone in the organization.")}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {comments.length === 0 ? (
              <p className="text-muted-foreground text-sm">
                {t("No comments yet.")}
              </p>
            ) : (
              <ol className="space-y-4" data-testid="comments">
                {comments.map((comment) => (
                  <li key={comment.id} className="space-y-1">
                    <p className="text-sm">
                      <span className="font-medium">
                        {(comment.authorId && names.get(comment.authorId)) ??
                          t("Someone")}
                      </span>{" "}
                      <span className="text-muted-foreground text-xs">
                        {format.dateTime(new Date(comment.createdAt), {
                          dateStyle: "medium",
                          timeStyle: "short",
                        })}
                      </span>
                    </p>
                    <p className="text-sm whitespace-pre-wrap">
                      {comment.body}
                    </p>
                  </li>
                ))}
              </ol>
            )}
            {can(session, "comments.create") ? (
              <CommentForm customerId={customer.id} />
            ) : null}
          </CardContent>
        </Card>
      </div>

      <div className="space-y-6">
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Recent notes")}</CardTitle>
          </CardHeader>
          <CardContent>
            {customer.notes.length === 0 ? (
              <p className="text-muted-foreground text-sm">
                {t("No notes yet.")}
              </p>
            ) : (
              <ul className="space-y-3">
                {customer.notes.map((note) => (
                  <li key={note.id} className="space-y-1 text-sm">
                    <p>{note.body}</p>
                    <Badge variant="outline">{note.kind}</Badge>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
        {can(session, "customers.write") ? (
          <Card size="sm">
            <CardContent>
              <CustomerLogoForm customerId={customer.id} />
            </CardContent>
          </Card>
        ) : null}
      </div>
    </div>
  );
}

export function CustomerDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="space-y-6 lg:col-span-2">
        <div className="flex items-center gap-4">
          <Skeleton className="size-14 rounded-xl" />
          <Skeleton className="h-8 w-48" />
        </div>
        <Skeleton className="h-72 rounded-xl" />
      </div>
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
