"use client";

import { useAction, useActionForm } from "better-supabase/react";
import { PlayIcon, SendIcon, SquareIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { startTimer, stopTimer, submitTimesheet } from "../people-actions";

/** Starts a timer on a project, or shows the running one with Stop. */
export function TimerControls({
  running,
}: {
  running: { readonly project: string; readonly since: string } | null;
}) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();

  const start = useActionForm(startTimer, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const stop = useAction(stopTimer, {
    onSuccess: () => {
      toast.success(t("Timer stopped"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  if (running) {
    return (
      <div className="flex items-center gap-2">
        <Badge variant="success-light">
          {t("{project} since {time}", {
            project: running.project === "" ? t("No project") : running.project,
            time: running.since,
          })}
        </Badge>
        <Button
          variant="outline"
          disabled={stop.pending}
          onClick={() => void stop.run({})}
        >
          <SquareIcon />
          {t("Stop")}
        </Button>
      </div>
    );
  }

  return (
    <form {...start.formProps} className="flex items-center gap-2">
      <Input
        name="project"
        required
        maxLength={200}
        placeholder={t("Project")}
        aria-label={t("Project to time")}
        className="w-40"
      />
      <Button type="submit" variant="outline" disabled={start.pending}>
        <PlayIcon />
        {t("Start timer")}
      </Button>
    </form>
  );
}

/** Sends the week for approval; it locks until someone rejects it. */
export function SubmitWeekButton({ week }: { week: string }) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();

  const submit = useAction(submitTimesheet, {
    onSuccess: () => {
      toast.success(t("Week submitted for approval"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button disabled={submit.pending} onClick={() => void submit.run({ week })}>
      <SendIcon />
      {t("Submit week")}
    </Button>
  );
}
