"use client";

import { useAction } from "better-supabase/react";
import { PauseIcon, PlayIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  createSchedule,
  pauseSchedule,
  removeSchedule,
} from "../workflows-actions";

function useToastErrors() {
  const errorMessage = useErrorMessage();
  return {
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };
}

export function ScheduleControls({
  id,
  paused,
}: {
  id: string;
  paused: boolean;
}) {
  const t = useExtracted("workflows");
  const handlers = useToastErrors();
  const pause = useAction(pauseSchedule, handlers);
  const remove = useAction(removeSchedule, handlers);
  return (
    <span className="flex gap-1">
      <Button
        variant="ghost"
        size="sm"
        disabled={pause.pending}
        aria-label={paused ? t("Resume") : t("Pause")}
        onClick={() => {
          void pause.run({ id, paused: !paused });
        }}
      >
        {paused ? <PlayIcon /> : <PauseIcon />}
      </Button>
      <Button
        variant="ghost"
        size="sm"
        disabled={remove.pending}
        aria-label={t("Remove")}
        onClick={() => {
          void remove.run({ id });
        }}
      >
        <Trash2Icon />
      </Button>
    </span>
  );
}

/** Schedules the onboarding drip every day at 09:00 UTC, or on the cron typed in. */
export function ScheduleForm() {
  const t = useExtracted("workflows");
  const handlers = useToastErrors();
  const create = useAction(createSchedule, {
    ...handlers,
    onSuccess: () => {
      toast.success(t("Schedule saved"));
    },
  });
  return (
    <form
      className="flex flex-wrap items-end gap-2"
      action={(form) => {
        void create.run({
          name: String(form.get("name") ?? ""),
          workflow: "onboarding-drip",
          cron: String(form.get("cron") ?? ""),
        });
      }}
    >
      <Input
        name="name"
        aria-label={t("Name")}
        defaultValue={t("Daily drip")}
        className="w-48"
      />
      <Input
        name="cron"
        aria-label={t("Cron")}
        defaultValue="0 9 * * *"
        className="w-40 font-mono"
      />
      <Button type="submit" variant="outline" disabled={create.pending}>
        {t("Save schedule")}
      </Button>
    </form>
  );
}
