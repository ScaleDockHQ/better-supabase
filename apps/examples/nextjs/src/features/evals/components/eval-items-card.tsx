"use client";

import { useAction } from "better-supabase/react";
import { ThumbsDownIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { addEvalItems, addEvalItemsFromFeedback } from "../evals-actions";

/** The dataset: its first items, a paste box and the feedback import. */
export function EvalItemsCard({
  name,
  items,
}: {
  name: string;
  items: readonly { id: string; input: string; expected: string }[];
}) {
  const t = useExtracted("evals");
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const [lines, setLines] = useState("");

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const add = useAction(addEvalItems, {
    onSuccess: (count) => {
      setLines("");
      toast.success(t("Added {count, number} items", { count }));
    },
    onError,
  });

  const fromFeedback = useAction(addEvalItemsFromFeedback, {
    onSuccess: (count) => {
      toast.success(t("Added {count, number} items from feedback", { count }));
    },
    onError,
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Dataset")}</CardTitle>
        <CardDescription>
          {t("{count, number} items. One per line as input => expected.", {
            count: items.length,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {items.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyTitle>{t("No items yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Paste a few lines below, or import the answers users rated down.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="divide-y rounded-lg border text-sm">
            {items.slice(0, 8).map((item) => (
              <li key={item.id} className="flex flex-col gap-0.5 px-3 py-2">
                <span>{item.input}</span>
                <span className="text-xs text-muted-foreground">
                  {item.expected === ""
                    ? t("No expected answer")
                    : item.expected}
                </span>
              </li>
            ))}
          </ul>
        )}
        <form
          className="flex flex-col gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            void add.run({ name, lines });
          }}
        >
          <Field>
            <FieldLabel htmlFor={`${fieldId}-lines`}>
              {t("Add items")}
            </FieldLabel>
            <Textarea
              id={`${fieldId}-lines`}
              value={lines}
              rows={4}
              placeholder="What is the refund window? => 30 days"
              onChange={(event) => {
                setLines(event.target.value);
              }}
            />
            <FieldDescription>
              {t(
                "An item without => has no expected answer and always fails the exact match.",
              )}
            </FieldDescription>
          </Field>
          <div className="flex flex-wrap justify-end gap-2">
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={fromFeedback.pending}
              onClick={() => {
                void fromFeedback.run({ name });
              }}
            >
              <ThumbsDownIcon />
              {t("Import rated-down answers")}
            </Button>
            <Button
              type="submit"
              size="sm"
              disabled={add.pending || lines.trim() === ""}
            >
              {t("Add items")}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
