"use client";

import { useAction } from "better-supabase/react";
import { KeyRoundIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ApiKeyRow } from "../api-key-queries";

import { revokeApiKey } from "../api-key-actions";

export function ApiKeyTable({ keys }: { keys: readonly ApiKeyRow[] }) {
  const t = useExtracted("apiKeys");
  const errorMessage = useErrorMessage();
  const format = useFormatter();
  const revoke = useAction(revokeApiKey, {
    onSuccess: () => {
      toast.success(t("Key revoked"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  const revoking = (id: string) =>
    revoke.pendingInputs.some((input) => input.id === id);
  if (keys.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <KeyRoundIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No API keys yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Create one to call the API from a script.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  const date = (value: string | null) =>
    value ? format.dateTime(new Date(value), { dateStyle: "medium" }) : "–";
  return (
    <Table data-testid="api-keys">
      <TableHeader>
        <TableRow>
          <TableHead>{t("Name")}</TableHead>
          <TableHead>{t("Key")}</TableHead>
          <TableHead className="hidden md:table-cell">{t("Created")}</TableHead>
          <TableHead className="hidden md:table-cell">
            {t("Last used")}
          </TableHead>
          <TableHead className="w-24" />
        </TableRow>
      </TableHeader>
      <TableBody>
        {keys.map((key) => (
          <TableRow
            key={key.id}
            aria-busy={revoking(key.id) ? true : undefined}
            className={revoking(key.id) ? "opacity-50" : undefined}
          >
            <TableCell className="font-medium">
              {key.name}{" "}
              {key.personal ? (
                <Badge variant="outline">{t("Personal")}</Badge>
              ) : null}
            </TableCell>
            <TableCell className="font-mono text-xs">{key.prefix}…</TableCell>
            <TableCell className="text-muted-foreground hidden md:table-cell">
              {date(key.createdAt)}
            </TableCell>
            <TableCell className="text-muted-foreground hidden md:table-cell">
              {date(key.lastUsedAt)}
            </TableCell>
            <TableCell className="text-right">
              {key.revoked ? (
                <Badge variant="secondary">{t("Revoked")}</Badge>
              ) : (
                <Button
                  variant="ghost"
                  size="sm"
                  disabled={revoking(key.id)}
                  onClick={() => {
                    void revoke.run({ id: key.id });
                  }}
                >
                  {t("Revoke")}
                </Button>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
