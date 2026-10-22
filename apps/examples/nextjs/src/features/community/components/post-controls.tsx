"use client";

import { useAction, useActionForm } from "better-supabase/react";
import { ChevronUpIcon, PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { createFeedbackBoard, createPost, voteOnPost } from "../posts-actions";

/** Opens the organization's feedback board. */
export function CreateBoardButton() {
  const t = useExtracted("community");
  const message = useErrorMessage();

  const create = useAction(createFeedbackBoard, {
    onSuccess: () => {
      toast.success(t("Feedback board opened"));
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      type="button"
      disabled={create.pending}
      onClick={() => {
        void create.run({ name: t("Feedback") });
      }}
    >
      <PlusIcon />
      {t("Open a feedback board")}
    </Button>
  );
}

/** Votes a post up, or clears the caller's vote. */
export function VoteButton({
  postId,
  score,
  voted,
  disabled,
}: {
  postId: string;
  score: number;
  voted: boolean;
  disabled: boolean;
}) {
  const t = useExtracted("community");
  const message = useErrorMessage();

  const vote = useAction(voteOnPost, {
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      type="button"
      variant={voted ? "secondary" : "outline"}
      aria-pressed={voted}
      aria-label={
        voted
          ? t("Remove your vote, {score} votes", { score: String(score) })
          : t("Vote up, {score} votes", { score: String(score) })
      }
      disabled={disabled || vote.pending}
      size="sm"
      className="tabular-nums"
      onClick={() => {
        void vote.run({ postId, value: voted ? 0 : 1 });
      }}
    >
      <ChevronUpIcon aria-hidden />
      {score}
    </Button>
  );
}

/** Writes a post on the board. */
export function NewPostDialog({ boardId }: { boardId: string }) {
  const t = useExtracted("community");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createPost, {
    onSuccess: (created) => {
      setOpen(false);
      toast.success(
        created.moderation === "pending"
          ? t("Posted; it shows once a moderator approves it")
          : t("Posted"),
      );
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button type="button" />}>
        <PlusIcon />
        {t("New post")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="boardId" value={boardId} />
          <DialogHeader>
            <DialogTitle>{t("New post")}</DialogTitle>
            <DialogDescription>
              {t("Share an idea; others vote on it and reply.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-body`}>
                {t("Details")}
              </FieldLabel>
              <Textarea id={`${fieldId}-body`} name="body" maxLength={10_000} />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Post")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
