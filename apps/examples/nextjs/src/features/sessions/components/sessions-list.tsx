"use client";

import { useSessionChange } from "better-supabase/next/client";
import { useAction } from "better-supabase/react";
import { LogOutIcon, MonitorIcon, MonitorSmartphoneIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";

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
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { sessionChanged } from "@/features/user/user-actions";
import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";
import { useErrorMessage } from "@/lib/use-error-message";

import type { CurrentSession, OtherSession } from "../sessions-queries";

import { endSession } from "../sessions-actions";

// #region recipe:sessions-list
/**
 * The caller's signed-in session with its sign-in method and time, and the
 * sessions on other devices (`list_my_sessions`). Each one can be ended on
 * its own (`end_my_session`), or all of them at once
 * (`signOut({ scope: "others" })`).
 */
export function SessionsList({
  session,
  others,
}: {
  session: CurrentSession;
  others: readonly OtherSession[];
}) {
  const t = useExtracted("sessions");
  const format = useFormatter();
  const supabase = useSupabase();
  const router = useRouter();
  const changeSession = useSessionChange(sessionChanged, router);
  const [othersOpen, setOthersOpen] = useState(false);
  const [endingOthers, startEndingOthers] = useTransition();
  const [endingThis, startEndingThis] = useTransition();

  const methodLabel = (method: string | null) => {
    switch (method) {
      case "password": {
        return t("Password");
      }

      case "otp":
      case "magiclink": {
        return t("Email link");
      }

      case "oauth": {
        return t("Social sign-in");
      }

      case "sso/saml": {
        return t("Single sign-on");
      }

      case "totp": {
        return t("Authenticator app");
      }

      case null: {
        return t("Unknown method");
      }

      default: {
        return method;
      }
    }
  };

  const signedIn = session.signedInAt
    ? format.dateTime(new Date(session.signedInAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : null;

  const endOthers = () => {
    startEndingOthers(async () => {
      const { error } = await supabase.auth.signOut({ scope: "others" });

      if (error) {
        toast.error(t("Signing out failed. Try again."));

        return;
      }

      setOthersOpen(false);
      toast.success(t("Signed out of your other devices"));
    });
  };

  const endThis = () => {
    startEndingThis(async () => {
      const { error } = await supabase.auth.signOut({ scope: "local" });

      if (error) {
        toast.error(t("Signing out failed. Try again."));

        return;
      }

      await changeSession("/login");
    });
  };

  return (
    <Card data-recipe="sessions-list">
      <CardHeader>
        <CardTitle>{t("Sessions")}</CardTitle>
        <CardDescription>
          {t(
            "The devices you are signed in on. End a session if you lost the device or signed in somewhere you no longer use.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-3 rounded-lg border p-3">
          <MonitorSmartphoneIcon
            aria-hidden="true"
            className="size-5 text-muted-foreground"
          />
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm font-medium">{t("This device")}</span>
              <Badge variant="success-light">{t("Active now")}</Badge>
              {session.aal === "aal2" ? (
                <Badge variant="info-light">{t("Two-factor")}</Badge>
              ) : null}
            </div>
            <span className="text-xs text-muted-foreground">
              {signedIn
                ? t("{method}, signed in {date}", {
                    date: signedIn,
                    method: methodLabel(session.method),
                  })
                : methodLabel(session.method)}
            </span>
          </div>
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={endingThis}
            onClick={endThis}
          >
            <LogOutIcon />
            {t("Sign out")}
          </Button>
        </div>
        {others.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("You are not signed in on any other device.")}
          </p>
        ) : (
          <ul className="flex flex-col gap-2">
            {others.map((other) => (
              <OtherSessionRow key={other.id} session={other} />
            ))}
          </ul>
        )}
        {others.length > 1 ? (
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm text-muted-foreground">
              {t("Other devices stay signed in until you end their sessions.")}
            </p>
            <AlertDialog
              open={othersOpen}
              onOpenChange={(open) => {
                if (!endingOthers) {
                  setOthersOpen(open);
                }
              }}
            >
              <AlertDialogTrigger
                render={<Button type="button" variant="outline" size="sm" />}
              >
                {t("Sign out other devices")}
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>
                    {t("Sign out of your other devices?")}
                  </AlertDialogTitle>
                  <AlertDialogDescription>
                    {t(
                      "Every session except this one ends. Those devices have to sign in again.",
                    )}
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel disabled={endingOthers}>
                    {t("Cancel")}
                  </AlertDialogCancel>
                  <AlertDialogAction
                    type="button"
                    variant="destructive"
                    disabled={endingOthers}
                    onClick={endOthers}
                  >
                    {t("Sign out others")}
                  </AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}

function OtherSessionRow({ session }: { session: OtherSession }) {
  const t = useExtracted("sessions");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const end = useAction(endSession, {
    onSuccess: () => {
      toast.success(t("Session ended"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const lastActive = format.dateTime(new Date(session.lastActiveAt), {
    dateStyle: "medium",
    timeStyle: "short",
  });

  return (
    <li className="flex flex-wrap items-center gap-3 rounded-lg border p-3">
      <MonitorIcon
        aria-hidden="true"
        className="size-5 text-muted-foreground"
      />
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <span className="truncate text-sm font-medium">
          {session.userAgent ?? t("Unknown device")}
        </span>
        <span className="text-xs text-muted-foreground">
          {session.ip
            ? t("Last active {date} from {ip}", {
                date: lastActive,
                ip: session.ip,
              })
            : t("Last active {date}", { date: lastActive })}
        </span>
      </div>
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={end.pending}
        onClick={() => {
          void end.run({ id: session.id });
        }}
      >
        {t("End session")}
      </Button>
    </li>
  );
}
// #endregion recipe:sessions-list
