"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";

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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/lib/toast";

import { installAgent, publishAgent, removeAgent } from "../agents-actions";

type Visibility = "private" | "organization" | "public";

/** Who sees the agent, whether the caller installed it, and delete. */
export function AgentPublish({
  id,
  visibility,
  installed,
  canPublish,
  canWrite,
}: {
  id: string;
  visibility: Visibility;
  installed: boolean;
  canPublish: boolean;
  canWrite: boolean;
}) {
  const t = useExtracted("agents");
  const router = useRouter();
  const errorMessage = useErrorMessage();

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const publish = useAction(publishAgent, { onError });
  const install = useAction(installAgent, { onError });

  const [confirmOpen, setConfirmOpen] = useState(false);

  const remove = useAction(removeAgent, {
    onSuccess: () => {
      setConfirmOpen(false);
      router.push("/assistant/agents");
    },
    onError,
  });

  const items = [
    { value: "private", label: t("Only the owner") },
    { value: "organization", label: t("The organization") },
    { value: "public", label: t("Everyone") },
  ];

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Sharing")}</CardTitle>
        <CardDescription>
          {t("Publish the agent to the store, or install it for yourself.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <Select
          value={visibility}
          items={items}
          disabled={!canPublish || publish.pending}
          onValueChange={(value) => {
            if (
              value === "private" ||
              value === "organization" ||
              value === "public"
            ) {
              void publish.run({ id, visibility: value });
            }
          }}
        >
          <SelectTrigger size="sm" aria-label={t("Visibility")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {items.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button
          size="sm"
          variant="outline"
          disabled={install.pending}
          onClick={() => {
            void install.run({ id, installed: !installed });
          }}
        >
          {installed ? t("Uninstall") : t("Install")}
        </Button>
        {canWrite ? (
          <AlertDialog
            open={confirmOpen}
            onOpenChange={(next) => {
              if (!remove.pending) {
                setConfirmOpen(next);
              }
            }}
          >
            <AlertDialogTrigger
              render={<Button size="sm" variant="destructive" />}
            >
              {t("Delete agent")}
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>{t("Delete this agent?")}</AlertDialogTitle>
                <AlertDialogDescription>
                  {t(
                    "The agent is removed for everyone who installed it. This cannot be undone.",
                  )}
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel disabled={remove.pending}>
                  {t("Cancel")}
                </AlertDialogCancel>
                <AlertDialogAction
                  variant="destructive"
                  disabled={remove.pending}
                  onClick={(event) => {
                    event.preventDefault();
                    void remove.run({ id });
                  }}
                >
                  {t("Delete")}
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        ) : null}
      </CardContent>
    </Card>
  );
}
