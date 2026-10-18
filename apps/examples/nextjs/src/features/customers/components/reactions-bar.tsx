"use client";

import { useReactions } from "better-supabase/blocks/reactions/react";
import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { blockConfig } from "@/lib/supabase/blocks.generated";

// #region recipe:reactions-bar

const EMOJIS = ["👍", "🎉", "❤️", "👀", "🚀"] as const;

/**
 * Quick reactions on the customer. The counts load in the browser and update
 * when anyone in the organization reacts (the `reactions` topic).
 */
export function ReactionsBar({
  organizationId,
  customerId,
  canReact,
}: {
  organizationId: string;
  customerId: string;
  canReact: boolean;
}) {
  const t = useExtracted("customers");
  const [busy, setBusy] = useState<string | null>(null);

  const { reactions, error, toggle, refresh } = useReactions({
    organizationId,
    subjectType: "customer",
    subjectIds: [customerId],
    topic: blockConfig.reactions.options.topic,
    schema: blockConfig.reactions.api,
  });

  const counts = new Map(
    (reactions?.[customerId] ?? []).map((each) => [each.emoji, each]),
  );

  const total = [...counts.values()].reduce((sum, each) => sum + each.count, 0);

  return (
    <Card size="sm" data-recipe="reactions-bar">
      <CardHeader>
        <CardTitle>{t("Reactions")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {error ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The reactions didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  void refresh();
                }}
              >
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : null}
        {reactions === undefined ? (
          error ? null : (
            <div className="flex gap-2">
              {EMOJIS.map((emoji) => (
                <Skeleton key={emoji} className="h-8 w-12" />
              ))}
            </div>
          )
        ) : (
          <div className="flex flex-col gap-2">
            <fieldset className="flex flex-wrap gap-2">
              <legend className="sr-only">{t("React to this customer")}</legend>
              {EMOJIS.map((emoji) => {
                const count = counts.get(emoji);

                return (
                  <Button
                    key={emoji}
                    size="sm"
                    variant={count?.reacted ? "secondary" : "outline"}
                    aria-pressed={count?.reacted ?? false}
                    disabled={!canReact || busy !== null}
                    onClick={() => {
                      setBusy(emoji);
                      void toggle(customerId, emoji).finally(() => {
                        setBusy(null);
                      });
                    }}
                  >
                    <span aria-hidden>{emoji}</span>
                    <span className="tabular-nums">{count?.count ?? 0}</span>
                  </Button>
                );
              })}
            </fieldset>
            {total === 0 ? (
              <p className="text-xs text-muted-foreground">
                {canReact
                  ? t("No reactions yet. Pick one to be the first.")
                  : t("No reactions yet.")}
              </p>
            ) : null}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// #endregion recipe:reactions-bar
