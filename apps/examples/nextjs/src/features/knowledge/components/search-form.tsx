"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import { searchKnowledge } from "../knowledge-actions";

const SCOPES = ["organization", "agent", "project", "chat", "user"] as const;

/**
 * A playground for the hybrid search the assistant's tool runs: pick the scope
 * and how many chunks to return, then read each hit with its fused score and
 * the chunk it came from.
 */
export function SearchForm() {
  const t = useExtracted("knowledge");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(searchKnowledge, { resetOnSuccess: false });
  const error = form.error === undefined ? null : errorMessage(form.error);

  const scopeItems = [
    { value: "", label: t("Every scope") },
    ...SCOPES.map((scope) => ({ value: scope, label: scope })),
  ];

  return (
    <div className="flex flex-col gap-4">
      <form {...form.formProps} className="flex flex-wrap items-end gap-3">
        <Field
          data-invalid={error ? true : undefined}
          className="min-w-64 flex-1"
        >
          <FieldLabel htmlFor={`${fieldId}-query`}>{t("Query")}</FieldLabel>
          <Input
            id={`${fieldId}-query`}
            name="query"
            required
            maxLength={500}
          />
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
        <Field className="w-36">
          <FieldLabel>{t("Scope")}</FieldLabel>
          <Select name="scope" defaultValue="" items={scopeItems}>
            <SelectTrigger size="sm" aria-label={t("Scope")}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {scopeItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field className="w-20">
          <FieldLabel htmlFor={`${fieldId}-k`}>{t("Hits")}</FieldLabel>
          <Input
            id={`${fieldId}-k`}
            name="k"
            type="number"
            min={1}
            max={20}
            defaultValue={5}
          />
        </Field>
        <label className="flex items-center gap-2 pb-2 text-sm">
          <Checkbox name="byScoreOnly" value="on" />
          {t("Rank by score only")}
        </label>
        <Button type="submit" size="sm" disabled={form.pending}>
          {t("Search")}
        </Button>
      </form>
      {form.data === undefined ? null : form.data.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t(
            "Nothing matches yet. A new document is searchable once it is ready.",
          )}
        </p>
      ) : (
        <ol className="divide-y rounded-xl border" data-testid="search-hits">
          {form.data.map((hit, index) => (
            <li key={hit.id} className="flex flex-col gap-1 px-4 py-3 text-sm">
              <p className="flex items-center gap-2 font-medium">
                <span className="text-muted-foreground tabular-nums">
                  {index + 1}
                </span>
                {hit.title}
                <span className="ml-auto font-mono text-xs font-normal text-muted-foreground tabular-nums">
                  {hit.score.toFixed(4)}
                </span>
              </p>
              <progress
                className="h-1 w-full"
                value={hit.best === 0 ? 0 : hit.score / hit.best}
                max={1}
                aria-label={t("Score relative to the best hit")}
              />
              <p className="line-clamp-3 text-muted-foreground">
                {hit.content}
              </p>
              <p className="font-mono text-xs text-muted-foreground">
                {hit.id}
              </p>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
