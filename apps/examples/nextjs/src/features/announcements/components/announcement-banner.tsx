"use client";

import { useAnnouncements } from "better-supabase/blocks/announcements/react";
import { MegaphoneIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

/**
 * The newest live announcement for this user and organization. Loads in
 * the browser and reloads on the module's broadcast, so it adds nothing to
 * the server render.
 */
export function AnnouncementBanner({
  organizationId,
}: {
  organizationId: string | null;
}) {
  const t = useExtracted("announcements");
  const { items, dismiss } = useAnnouncements({
    organizationId,
    schema: "api",
  });
  const announcement = items?.[0];
  if (!announcement) return null;
  return (
    <Alert
      variant={announcement.severity === "critical" ? "destructive" : "default"}
      data-testid="announcement"
    >
      <MegaphoneIcon />
      <AlertTitle>{announcement.title}</AlertTitle>
      {announcement.body ? (
        <AlertDescription>{announcement.body}</AlertDescription>
      ) : null}
      {announcement.dismissible ? (
        <AlertAction>
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t("Dismiss")}
            onClick={() => void dismiss(announcement.id)}
          >
            <XIcon />
          </Button>
        </AlertAction>
      ) : null}
    </Alert>
  );
}
