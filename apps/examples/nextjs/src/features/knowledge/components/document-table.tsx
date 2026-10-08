"use client";

import { useAction } from "better-supabase/react";
import { Trash2Icon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useErrorMessage } from "@/lib/use-error-message";

import type { DocumentRow } from "../knowledge-queries";

import { removeDocument } from "../knowledge-actions";

function StatusBadge({ status }: { status: DocumentRow["status"] }) {
  const t = useExtracted("knowledge");
  switch (status) {
    case "pending":
      return <Badge variant="secondary">{t("Embedding")}</Badge>;
    case "ready":
      return <Badge variant="outline">{t("Ready")}</Badge>;
    case "failed":
      return <Badge variant="destructive">{t("Failed")}</Badge>;
    default: {
      const unknown: never = status;
      return unknown;
    }
  }
}

export function DocumentTable({
  documents,
}: {
  documents: readonly DocumentRow[];
}) {
  const t = useExtracted("knowledge");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const remove = useAction(removeDocument, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  if (documents.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">
        {t("No documents yet. Add one above.")}
      </p>
    );
  }
  return (
    <Table data-testid="documents">
      <TableHeader>
        <TableRow>
          <TableHead>{t("Title")}</TableHead>
          <TableHead>{t("Status")}</TableHead>
          <TableHead className="text-right">{t("Chunks")}</TableHead>
          <TableHead>{t("Added")}</TableHead>
          <TableHead>
            <span className="sr-only">{t("Actions")}</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {documents.map((document) => (
          <TableRow key={document.id}>
            <TableCell className="font-medium">{document.title}</TableCell>
            <TableCell>
              <StatusBadge status={document.status} />
            </TableCell>
            <TableCell className="text-right tabular-nums">
              {document.chunks}
            </TableCell>
            <TableCell className="text-muted-foreground">
              {format.dateTime(new Date(document.createdAt), {
                dateStyle: "medium",
              })}
            </TableCell>
            <TableCell className="text-right">
              <Button
                variant="ghost"
                size="icon-sm"
                disabled={remove.pendingInputs.some(
                  (input) => input.id === document.id,
                )}
                aria-label={t("Delete {title}", { title: document.title })}
                onClick={() => {
                  void remove.run({ id: document.id });
                }}
              >
                <Trash2Icon />
              </Button>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
