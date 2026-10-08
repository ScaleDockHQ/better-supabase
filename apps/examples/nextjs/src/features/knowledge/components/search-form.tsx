"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { searchKnowledge } from "../knowledge-actions";

/** A playground for the hybrid search the assistant's tool runs. */
export function SearchForm() {
  const t = useExtracted("knowledge");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(searchKnowledge, { resetOnSuccess: false });
  const error = form.error === undefined ? null : errorMessage(form.error);
  return (
    <div className="space-y-4">
      <form {...form.formProps} className="flex items-end gap-2">
        <Field data-invalid={error ? true : undefined} className="flex-1">
          <FieldLabel htmlFor={`${fieldId}-query`}>{t("Query")}</FieldLabel>
          <Input
            id={`${fieldId}-query`}
            name="query"
            required
            maxLength={500}
          />
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
        <Button type="submit" size="sm" disabled={form.pending}>
          {t("Search")}
        </Button>
      </form>
      {form.data === undefined ? null : form.data.length === 0 ? (
        <p className="text-muted-foreground text-sm">
          {t(
            "Nothing matches yet. A new document is searchable once it is ready.",
          )}
        </p>
      ) : (
        <ol className="divide-y rounded-xl border" data-testid="search-hits">
          {form.data.map((hit) => (
            <li key={hit.id} className="space-y-1 px-4 py-3 text-sm">
              <p className="font-medium">{hit.title}</p>
              <p className="text-muted-foreground line-clamp-3">
                {hit.content}
              </p>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
