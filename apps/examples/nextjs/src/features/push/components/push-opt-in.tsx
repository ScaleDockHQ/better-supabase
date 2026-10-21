// #region recipe:push-opt-in
"use client";

import { createPush, rpcTransport } from "better-supabase/blocks/push";
import { webPushToken } from "better-supabase/client";
import { BellOffIcon, BellRingIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useEffect, useState, useTransition } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardAction,
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
import { useSupabase } from "@/lib/hooks";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/**
 * The worker in `public/` that shows the pushes; it must be served from the
 * site root.
 */
const WORKER_URL = "/push-sw.js";
const PUSH_GUIDE = "https://bettersupabase.com/docs/blocks/push";

const VAPID_PUBLIC_KEY = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

type PushState =
  | { readonly kind: "checking" }
  | { readonly kind: "unsupported" }
  | { readonly kind: "unconfigured" }
  | { readonly kind: "denied" }
  | { readonly kind: "off" }
  | { readonly kind: "on"; readonly token: string }
  | { readonly kind: "error" };

function supportsPush(): boolean {
  return (
    "serviceWorker" in navigator &&
    "PushManager" in window &&
    "Notification" in window
  );
}

/** What the browser already has, without asking the user anything. */
async function currentState(): Promise<PushState> {
  if (!supportsPush()) {
    return { kind: "unsupported" };
  }

  if (!VAPID_PUBLIC_KEY) {
    return { kind: "unconfigured" };
  }

  if (Notification.permission === "denied") {
    return { kind: "denied" };
  }

  const registration =
    await navigator.serviceWorker.getRegistration(WORKER_URL);

  const subscription = await registration?.pushManager.getSubscription();

  return subscription
    ? { kind: "on", token: JSON.stringify(subscription) }
    : { kind: "off" };
}

/**
 * Asks for web push permission and stores this browser's push subscription as
 * one of the caller's devices in the push module (`register_push_device`), or
 * removes it again. The device row belongs to the signed-in user, so a sender
 * can reach every browser they turned on.
 */
export function PushOptIn() {
  const t = useExtracted("push");
  const supabase = useSupabase();
  const [state, setState] = useState<PushState>({ kind: "checking" });
  const [pending, startTransition] = useTransition();

  const devices = createPush({
    transport: rpcTransport(supabase),
    schema: blockConfig.push.api,
  });

  const read = () => {
    currentState().then(setState, () => {
      setState({ kind: "error" });
    });
  };

  const check = () => {
    setState({ kind: "checking" });
    read();
  };

  useEffect(read, []);

  const turnOn = () => {
    startTransition(async () => {
      if (!VAPID_PUBLIC_KEY) {
        return;
      }

      try {
        await navigator.serviceWorker.register(WORKER_URL);

        const token = await webPushToken({
          vapidPublicKey: VAPID_PUBLIC_KEY,
        }).token();

        if (token === null) {
          setState(
            Notification.permission === "denied"
              ? { kind: "denied" }
              : { kind: "off" },
          );

          return;
        }

        const saved = await devices.register({
          token,
          platform: "web",
          provider: "webpush",
        });

        setState(saved.ok ? { kind: "on", token } : { kind: "error" });
      } catch {
        setState({ kind: "error" });
      }
    });
  };

  const turnOff = (token: string) => {
    startTransition(async () => {
      const removed = await devices.unregister(token);

      if (!removed.ok) {
        setState({ kind: "error" });

        return;
      }

      const registration =
        await navigator.serviceWorker.getRegistration(WORKER_URL);

      await (await registration?.pushManager.getSubscription())?.unsubscribe();
      setState({ kind: "off" });
    });
  };

  return (
    <Card data-testid="push-opt-in" data-recipe="push-opt-in">
      <CardHeader>
        <CardTitle>{t("Push notifications")}</CardTitle>
        <CardDescription>
          {t("Get a notification on this device when something needs you.")}
        </CardDescription>
        {state.kind === "on" ? (
          <CardAction>
            <Badge variant="success-light">{t("On")}</Badge>
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        <PushStateBody
          state={state}
          pending={pending}
          onTurnOn={turnOn}
          onTurnOff={turnOff}
          onRetry={check}
        />
      </CardContent>
    </Card>
  );
}

function PushStateBody({
  state,
  pending,
  onTurnOn,
  onTurnOff,
  onRetry,
}: {
  state: PushState;
  pending: boolean;
  onTurnOn: () => void;
  onTurnOff: (token: string) => void;
  onRetry: () => void;
}) {
  const t = useExtracted("push");

  switch (state.kind) {
    case "checking": {
      return (
        <div className="flex items-center gap-3" aria-busy="true">
          <Skeleton className="h-4 flex-1" />
          <Skeleton className="h-8 w-24" />
        </div>
      );
    }

    case "unsupported": {
      return (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <BellOffIcon />
            </EmptyMedia>
            <EmptyTitle>{t("This browser has no push support")}</EmptyTitle>
            <EmptyDescription>
              {t(
                "Open the app in a browser that supports web push, or install it to your home screen on iOS.",
              )}
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <a
              href={PUSH_GUIDE}
              className={buttonVariants({ variant: "outline" })}
            >
              {t("Read the push guide")}
            </a>
          </EmptyContent>
        </Empty>
      );
    }

    case "unconfigured": {
      return (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <BellOffIcon />
            </EmptyMedia>
            <EmptyTitle>{t("Push isn't set up yet")}</EmptyTitle>
            <EmptyDescription>
              {t(
                "Set NEXT_PUBLIC_VAPID_PUBLIC_KEY to your VAPID public key to turn on web push.",
              )}
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <a
              href={PUSH_GUIDE}
              className={buttonVariants({ variant: "outline" })}
            >
              {t("Read the push guide")}
            </a>
          </EmptyContent>
        </Empty>
      );
    }

    case "denied": {
      return (
        <p className="text-sm text-muted-foreground">
          {t(
            "Notifications are blocked for this site. Allow them in your browser's site settings, then reload the page.",
          )}
        </p>
      );
    }

    case "off": {
      return (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-muted-foreground">
            {t("Your browser asks for permission first.")}
          </p>
          <Button onClick={onTurnOn} disabled={pending}>
            <BellRingIcon />
            {t("Turn on")}
          </Button>
        </div>
      );
    }

    case "on": {
      return (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-muted-foreground">
            {t("This browser gets your push notifications.")}
          </p>
          <Button
            variant="outline"
            onClick={() => {
              onTurnOff(state.token);
            }}
            disabled={pending}
          >
            {t("Turn off")}
          </Button>
        </div>
      );
    }

    case "error": {
      return (
        <Alert variant="destructive">
          <TriangleAlertIcon />
          <AlertTitle>{t("Push couldn't be updated")}</AlertTitle>
          <AlertDescription>
            {t("Check your connection and try again.")}
          </AlertDescription>
          <AlertAction>
            <Button size="sm" variant="outline" onClick={onRetry}>
              {t("Retry")}
            </Button>
          </AlertAction>
        </Alert>
      );
    }

    default: {
      const unknown: never = state;

      return unknown;
    }
  }
}
// #endregion recipe:push-opt-in
