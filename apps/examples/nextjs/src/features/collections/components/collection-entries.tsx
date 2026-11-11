"use client";

import { useAction } from "better-supabase/react";
import { XIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Link } from "@/i18n/navigation";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { CollectionEntryRow } from "../collections-queries";

import { addToCollection, removeFromCollection } from "../collections-actions";

/** The entries of a collection, with a picker to add a customer. */
export function CollectionEntries({
  collectionId,
  entries,
  candidates,
  canWrite,
}: {
  collectionId: string;
  entries: readonly CollectionEntryRow[];
  candidates: readonly { readonly id: string; readonly name: string }[];
  canWrite: boolean;
}) {
  const t = useExtracted("collections");
  const errorMessage = useErrorMessage();

  const callbacks = {
    onSuccess: () => {
      toast.success(t("Collection updated"));
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };

  const add = useAction(addToCollection, callbacks);
  const remove = useAction(removeFromCollection, callbacks);

  return (
    <div className="flex flex-col gap-4">
      {canWrite && candidates.length > 0 ? (
        <Select<string>
          items={candidates.map((row) => ({ value: row.id, label: row.name }))}
          onValueChange={(value) => {
            if (value) {
              void add.run({ collectionId, subjectId: value });
            }
          }}
        >
          <SelectTrigger className="w-64" disabled={add.pending}>
            <SelectValue placeholder={t("Add a customer")} />
          </SelectTrigger>
          <SelectContent>
            {candidates.map((row) => (
              <SelectItem key={row.id} value={row.id}>
                {row.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      ) : null}
      {entries.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t("Nothing in this collection yet.")}
        </p>
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {entries.map((entry) => (
            <li
              key={entry.subjectId}
              className="flex items-center justify-between gap-2"
            >
              <Link
                href={`/customers/${entry.subjectId}`}
                className="hover:underline"
              >
                {entry.title}
              </Link>
              {canWrite ? (
                <Button
                  size="icon-sm"
                  variant="ghost"
                  aria-label={t("Remove {title}", { title: entry.title })}
                  disabled={remove.pending}
                  onClick={() => {
                    void remove.run({
                      collectionId,
                      subjectId: entry.subjectId,
                    });
                  }}
                >
                  <XIcon />
                </Button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
