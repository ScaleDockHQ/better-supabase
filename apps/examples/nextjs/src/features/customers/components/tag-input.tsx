// #region recipe:tag-input
"use client";

import { useTagInput } from "better-supabase/blocks/tags/react";
import { XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { type SubmitEvent, useId, useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

/**
 * A record's tags. Typing a name adds the organization's tag of the
 * subject's kind with that name, or creates it for callers with
 * `tags.manage`.
 */
export function TagInput({
  organizationId,
  subject,
}: {
  organizationId: string;
  subject: { readonly type: string; readonly id: string };
}) {
  const t = useExtracted("customers");
  const listId = useId();
  const errorMessage = useErrorMessage();
  const [name, setName] = useState("");

  const { tags, available, pending, error, create, remove } = useTagInput({
    organizationId,
    subjectType: subject.type,
    subjectId: subject.id,
    kind: subject.type,
    schema: blockConfig.tags.api,
  });

  const applied = new Set(tags?.map((tag) => tag.id));
  const suggestions = available?.filter((tag) => !applied.has(tag.id)) ?? [];

  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!name.trim()) {
      return;
    }

    if ((await create(name)).ok) {
      setName("");
    }
  };

  if (tags === undefined) {
    return <Skeleton className="h-16" />;
  }

  return (
    <div className="space-y-3">
      <ul className="flex flex-wrap gap-1.5" data-testid="tags">
        {tags.length === 0 ? (
          <li className="text-sm text-muted-foreground">{t("No tags yet.")}</li>
        ) : null}
        {tags.map((tag) => (
          <li key={tag.id}>
            <Badge
              variant="secondary"
              className={pending.includes(tag.id) ? "opacity-50" : undefined}
            >
              {tag.name}
              <button
                type="button"
                aria-label={t("Remove {name}", { name: tag.name })}
                disabled={pending.includes(tag.id)}
                onClick={() => {
                  void remove(tag.id);
                }}
              >
                <XIcon className="size-3" />
              </button>
            </Badge>
          </li>
        ))}
      </ul>
      <form onSubmit={(event) => void submit(event)} className="flex gap-2">
        <Input
          value={name}
          onChange={(event) => {
            setName(event.target.value);
          }}
          list={listId}
          maxLength={80}
          placeholder={t("Add a tag")}
          aria-label={t("Tag")}
        />
        <datalist id={listId}>
          {suggestions.map((tag) => (
            <option key={tag.id} value={tag.name}>
              {tag.name}
            </option>
          ))}
        </datalist>
        <Button type="submit" variant="outline" disabled={!name.trim()}>
          {t("Add")}
        </Button>
      </form>
      {error ? (
        <p className="text-sm text-destructive">{errorMessage(error)}</p>
      ) : null}
    </div>
  );
}
// #endregion recipe:tag-input
