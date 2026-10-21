// #region recipe:comment-thread
"use client";

import type { SubmitEvent } from "react";

import { useComments } from "better-supabase/blocks/comments/react";
import { useExtracted, useFormatter } from "next-intl";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

/**
 * A record's comments, oldest first, through the browser client. `subject` is
 * any type in `config.subjects`, such as a customer or a project.
 */
export function CommentThread({
  subject,
  authors,
  canComment,
}: {
  subject: { readonly type: string; readonly id: string };
  /** Display names by user id. */
  authors: Readonly<Record<string, string>>;
  canComment: boolean;
}) {
  const t = useExtracted("customers");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const [body, setBody] = useState("");
  const [pending, setPending] = useState(false);

  const { comments, error, add } = useComments({ subject });

  const visible = comments?.filter((comment) => !comment.deletedAt);

  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = body.trim();

    if (!text) {
      return;
    }

    setPending(true);

    if ((await add(text)).ok) {
      setBody("");
    }

    setPending(false);
  };

  return (
    <div className="space-y-6">
      {visible === undefined ? (
        <Skeleton className="h-16" />
      ) : visible.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("No comments yet.")}</p>
      ) : (
        <ol className="space-y-4" data-testid="comments">
          {visible.map((comment) => (
            <li key={comment.id} className="space-y-1">
              <p className="text-sm">
                <span className="font-medium">
                  {(comment.authorId && authors[comment.authorId]) ??
                    t("Someone")}
                </span>{" "}
                <span className="text-xs text-muted-foreground">
                  {format.dateTime(comment.createdAt.epochMilliseconds, {
                    dateStyle: "medium",
                    timeStyle: "short",
                  })}
                </span>
              </p>
              <p className="text-sm whitespace-pre-wrap">{comment.body}</p>
            </li>
          ))}
        </ol>
      )}
      {canComment ? (
        <form onSubmit={(event) => void submit(event)} className="space-y-3">
          <Field data-invalid={error ? true : undefined}>
            <FieldLabel htmlFor={`${fieldId}-comment-body`} className="sr-only">
              {t("Comment")}
            </FieldLabel>
            <Textarea
              id={`${fieldId}-comment-body`}
              value={body}
              onChange={(event) => {
                setBody(event.target.value);
              }}
              placeholder={t("Write a comment")}
              required
              maxLength={4000}
              rows={3}
            />
            {error ? <FieldError>{errorMessage(error)}</FieldError> : null}
          </Field>
          <Button type="submit" size="sm" disabled={pending}>
            {t("Comment")}
          </Button>
        </form>
      ) : null}
    </div>
  );
}
// #endregion recipe:comment-thread
