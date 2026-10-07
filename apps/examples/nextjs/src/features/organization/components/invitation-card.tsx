import { MailIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { RoleBadge } from "@/features/user/components/role-badge";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { getInvitationPreview } from "../invitation-queries";
import { InvitationResponse } from "./invitation-response";

/** Render inside `<Suspense>`: reads the `token` param and the session. */
export async function InvitationCard({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const [preview, session, t, format, locale] = await Promise.all([
    getInvitationPreview(token),
    getSession(),
    getExtracted("invitation"),
    getFormatter(),
    getLocale(),
  ]);
  if (preview?.status !== "pending") {
    return (
      <Card>
        <CardHeader className="text-center">
          <CardTitle className="text-xl">
            {t("This invitation can't be used")}
          </CardTitle>
          <CardDescription>
            {preview?.status === "expired"
              ? t("It expired. Ask for a new one.")
              : t("It was already used, revoked or never existed.")}
          </CardDescription>
        </CardHeader>
        <CardFooter>
          <Link href="/" className={buttonVariants({ className: "w-full" })}>
            {t("Go to the dashboard")}
          </Link>
        </CardFooter>
      </Card>
    );
  }
  const back = `/${locale}/invite/${encodeURIComponent(token)}`;
  const signedIn = session.kind === "user";
  return (
    <Card data-testid="invitation">
      <CardHeader className="text-center">
        <MailIcon className="text-primary mx-auto size-8" />
        <CardTitle className="text-xl">
          {t("Join {organization}", {
            organization: preview.organizationName ?? "",
          })}
        </CardTitle>
        <CardDescription>
          {t("Invitation for {email}, valid until {date}.", {
            email: preview.email,
            date: format.dateTime(new Date(preview.expiresAt), {
              dateStyle: "long",
            }),
          })}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex justify-center">
        <RoleBadge role={preview.role} />
      </CardContent>
      <CardFooter className="flex-col gap-2">
        {signedIn ? (
          <>
            {session.user.email === preview.email ? null : (
              <p className="text-muted-foreground text-center text-sm">
                {t(
                  "You're signed in as {email}. The invitation only works for its own address.",
                  {
                    email: session.user.email ?? "",
                  },
                )}
              </p>
            )}
            <InvitationResponse token={token} />
          </>
        ) : (
          <>
            <Link
              href={{ pathname: "/signup", query: { next: back } }}
              className={buttonVariants({ className: "w-full" })}
            >
              {t("Create an account")}
            </Link>
            <Link
              href={{ pathname: "/login", query: { next: back } }}
              className={buttonVariants({
                variant: "outline",
                className: "w-full",
              })}
            >
              {t("I already have one")}
            </Link>
          </>
        )}
      </CardFooter>
    </Card>
  );
}

export function InvitationCardSkeleton() {
  return <Skeleton className="h-80 rounded-xl" aria-busy="true" />;
}
