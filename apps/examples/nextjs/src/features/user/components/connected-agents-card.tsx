"use client";

import { useSessionChange } from "better-supabase/next/client";
import { useExtracted, useFormatter } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useSupabase } from "@/lib/hooks";

import type { AuthRead, Grant } from "../security-queries";

import { sessionChanged } from "../user-actions";

/**
 * The OAuth clients (MCP servers, agents) this user approved on the consent
 * page. The server reads them (`getGrants`), so they are in the
 * prefetched page; disconnecting runs in the browser.
 */
export function ConnectedAgentsCard({
  initial,
}: {
  readonly initial: AuthRead<readonly Grant[]>;
}) {
  const t = useExtracted("security");
  const format = useFormatter();
  const supabase = useSupabase();
  const changeSession = useSessionChange(sessionChanged);
  const [grants, setGrants] = useState<readonly Grant[]>(
    initial.ok ? initial.value : [],
  );
  const error = initial.ok ? null : initial.error;
  const [pending, startTransition] = useTransition();

  const revoke = (grant: Grant) => {
    startTransition(async () => {
      const { error: revokeError } = await supabase.auth.oauth.revokeGrant({
        clientId: grant.client.id,
      });
      if (revokeError) {
        toast.error(revokeError.message);
        return;
      }
      setGrants((current) =>
        current.filter((item) => item.client.id !== grant.client.id),
      );
      await changeSession();
      toast.success(
        t("{client} is disconnected.", { client: grant.client.name }),
      );
    });
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Connected agents")}</CardTitle>
        <CardDescription>
          {t(
            "Apps and AI agents you allowed to act as you. Disconnecting one ends its sessions; a token it already holds works until it expires.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {error ? (
          <p className="text-destructive text-sm">{error}</p>
        ) : grants.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            {t("No agents are connected.")}
          </p>
        ) : (
          <ul className="divide-y" data-testid="connected-agents">
            {grants.map((grant) => (
              <li
                key={grant.client.id}
                className="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
              >
                <div className="min-w-0 text-sm">
                  <p className="truncate font-medium">{grant.client.name}</p>
                  <p className="text-muted-foreground truncate">
                    {t("Connected {date}", {
                      date: format.dateTime(new Date(grant.granted_at), {
                        dateStyle: "medium",
                      }),
                    })}
                    {grant.scopes.length > 0
                      ? ` · ${grant.scopes.join(", ")}`
                      : null}
                  </p>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={pending}
                  onClick={() => {
                    revoke(grant);
                  }}
                >
                  {t("Disconnect")}
                </Button>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
