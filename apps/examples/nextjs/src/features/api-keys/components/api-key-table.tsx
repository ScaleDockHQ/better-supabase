// #region recipe:api-keys-table
"use client";

import { useApiKeys } from "better-supabase/blocks/api-keys/react";
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
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

import { apiKeyCreated } from "../api-key-actions";
import { CreateApiKeyDialog } from "./create-api-key-dialog";

/**
 * The organization's API keys through the browser client, with a button
 * that creates one and shows its token once. Members without
 * `api_keys.manage` create `personal` keys, which act as them.
 */
export function ApiKeyTable({
  organizationId,
  personal,
}: {
  organizationId: string;
  personal: boolean;
}) {
  const t = useExtracted("apiKeys");
  const errorMessage = useErrorMessage();
  const format = useFormatter();
  const { keys, created, creating, revoking, error, create, revoke, dismiss } =
    useApiKeys({
      organizationId,
      schema: blockConfig["api-keys"].api,
      onChanged: async ({ kind }) => {
        if (kind === "created") {
          await apiKeyCreated({});
        }
      },
    });

  const revokeKey = async (id: string) => {
    const result = await revoke(id);
    if (result.ok) {
      toast.success(t("Key revoked"));
    } else {
      toast.error(errorMessage(result.error));
    }
  };
  const date = (value: Temporal.Instant | undefined) =>
    value
      ? format.dateTime(new Date(value.epochMilliseconds), {
          dateStyle: "medium",
        })
      : "–";

  const dialog = (
    <CreateApiKeyDialog
      token={created?.token}
      creating={creating}
      error={error}
      onCreate={async (name) => {
        await create({ name, personal });
      }}
      onClose={dismiss}
    />
  );
  if (keys === undefined) {
    return (
      <div className="grid gap-4">
        <div className="flex justify-end">{dialog}</div>
        <Skeleton className="h-32" />
      </div>
    );
  }
  return (
    <div className="grid gap-4">
      <div className="flex justify-end">{dialog}</div>
      {keys.length === 0 ? (
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
      ) : (
        <Table data-testid="api-keys">
          <TableHeader>
            <TableRow>
              <TableHead>{t("Name")}</TableHead>
              <TableHead>{t("Key")}</TableHead>
              <TableHead className="hidden md:table-cell">
                {t("Created")}
              </TableHead>
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
                aria-busy={revoking.includes(key.id) ? true : undefined}
                className={revoking.includes(key.id) ? "opacity-50" : undefined}
              >
                <TableCell className="font-medium">
                  {key.name}{" "}
                  {key.userId ? (
                    <Badge variant="outline">{t("Personal")}</Badge>
                  ) : null}
                </TableCell>
                <TableCell className="font-mono text-xs">
                  {key.prefix}_{key.publicId}…
                </TableCell>
                <TableCell className="hidden text-muted-foreground md:table-cell">
                  {date(key.createdAt)}
                </TableCell>
                <TableCell className="hidden text-muted-foreground md:table-cell">
                  {date(key.lastUsedAt)}
                </TableCell>
                <TableCell className="text-right">
                  {key.state === "revoked" || key.state === "expired" ? (
                    <Badge variant="secondary">{t("Revoked")}</Badge>
                  ) : (
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={revoking.includes(key.id)}
                      onClick={() => {
                        void revokeKey(key.id);
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
      )}
    </div>
  );
}
// #endregion recipe:api-keys-table
