// #region recipe:comment-thread
"use client";

import { useComments } from "better-supabase/blocks/comments/react";
import { useExtracted, useFormatter } from "next-intl";
import { type SubmitEvent, useId, useState } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

/** A customer's comments, oldest first, through the browser client. */
export function CommentThread({
  organizationId,
  customerId,
  authors,
  canComment,
}: {
  organizationId: string;
  customerId: string;
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
  const { comments, error, add } = useComments({
    organizationId,
    subjectType: "customer",
    subjectId: customerId,
    schema: blockConfig.comments.api,
  });
  const visible = comments?.filter((comment) => !comment.deletedAt);

  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = body.trim();
    if (!text) return;
    setPending(true);
    if ((await add(text)).ok) setBody("");
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
