"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { ArrowDownIcon, ArrowUpIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { toast } from "@/lib/toast";

import type { ProviderKeyRow } from "../ai-providers-queries";

import { setProviderRouting } from "../ai-providers-actions";

const rank = (key: ProviderKeyRow): number =>
  key.priority ?? Number.MAX_SAFE_INTEGER;

/**
 * The failover order of the organization's provider keys. The assistant sends
 * the order to the AI Gateway, which tries the first enabled provider and moves
 * on when it fails. A change waits for Save.
 */
export function ProviderRouting({
  keys,
  canManage,
}: {
  keys: readonly ProviderKeyRow[];
  canManage: boolean;
}) {
  const t = useExtracted("aiProviders");
  const errorMessage = useErrorMessage();

  const [draft, setDraft] = useState(() =>
    keys
      .toSorted((a, b) => rank(a) - rank(b))
      .map((key) => ({ id: key.id, enabled: key.enabled })),
  );

  const save = useAction(setProviderRouting, {
    onSuccess: () => {
      toast.success(t("Routing saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  if (keys.length < 2) {
    return null;
  }

  const byId = new Map(keys.map((key) => [key.id, key]));

  const move = (index: number, by: -1 | 1) => {
    setDraft((current) => {
      const next = [...current];
      const [entry] = next.splice(index, 1);

      if (entry !== undefined) {
        next.splice(index + by, 0, entry);
      }

      return next;
    });
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Routing and failover")}</CardTitle>
        <CardDescription>
          {t(
            "The first enabled provider answers. When it fails, the gateway tries the next one.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <ol className="flex flex-col gap-2">
          {draft.map((entry, index) => {
            const key = byId.get(entry.id);

            return key === undefined ? null : (
              <li
                key={entry.id}
                className="flex items-center gap-3 rounded-lg border px-3 py-2 text-sm"
              >
                <span className="w-5 text-muted-foreground tabular-nums">
                  {index + 1}
                </span>
                <span className="font-medium">{key.provider}</span>
                <Badge variant="secondary">{key.name}</Badge>
                <span className="ml-auto flex items-center gap-1">
                  <Switch
                    checked={entry.enabled}
                    disabled={!canManage}
                    aria-label={t("Use {provider}", { provider: key.provider })}
                    onCheckedChange={(checked) => {
                      setDraft((current) =>
                        current.map((candidate) =>
                          candidate.id === entry.id
                            ? { ...candidate, enabled: checked }
                            : candidate,
                        ),
                      );
                    }}
                  />
                  <Button
                    size="icon-sm"
                    variant="ghost"
                    disabled={!canManage || index === 0}
                    aria-label={t("Move up")}
                    onClick={() => {
                      move(index, -1);
                    }}
                  >
                    <ArrowUpIcon />
                  </Button>
                  <Button
                    size="icon-sm"
                    variant="ghost"
                    disabled={!canManage || index === draft.length - 1}
                    aria-label={t("Move down")}
                    onClick={() => {
                      move(index, 1);
                    }}
                  >
                    <ArrowDownIcon />
                  </Button>
                </span>
              </li>
            );
          })}
        </ol>
        {canManage ? (
          <div className="flex justify-end">
            <Button
              size="sm"
              disabled={save.pending}
              onClick={() => {
                void save.run({ keys: draft });
              }}
            >
              {t("Save routing")}
            </Button>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
