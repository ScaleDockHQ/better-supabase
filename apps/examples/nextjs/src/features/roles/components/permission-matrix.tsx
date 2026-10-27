"use client";

import type { PermissionSet } from "better-supabase/blocks/permissions";

import { can as holds } from "better-supabase/blocks/permissions";
import { useAction } from "better-supabase/react";
import { RotateCcwIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useOptimistic, useState, useTransition } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useErrorMessage } from "@/lib/use-error-message";

import { setPermissionOverride } from "../roles-actions";

/** The keys grouped by the part before the first dot, groups sorted. */
function groupKeys(
  keys: readonly string[],
): readonly (readonly [string, readonly string[]])[] {
  const groups = new Map<string, string[]>();

  for (const key of keys) {
    const group = key.slice(0, key.indexOf("."));
    groups.set(group, [...(groups.get(group) ?? []), key]);
  }

  return [...groups.entries()].toSorted(([a], [b]) => a.localeCompare(b));
}

type Change = { readonly permission: string; readonly granted: boolean | null };

/**
 * One role's keys in the organization: the catalog default next to what the
 * role holds here. A switch writes an override, Reset removes it. Changes show
 * at once and roll back when `set_permission_override` refuses them. A key the
 * caller doesn't hold stays read-only, as the database requires.
 */
export function PermissionMatrix({
  roleId,
  keys,
  defaults,
  effective,
  held,
  editable,
}: {
  roleId: string;
  keys: readonly string[];
  defaults: readonly string[];
  effective: readonly string[];
  held: PermissionSet | null;
  editable: boolean;
}) {
  const t = useExtracted("roles");
  const searchId = useId();
  const errorMessage = useErrorMessage();
  const [search, setSearch] = useState("");
  const [, startTransition] = useTransition();

  const [granted, apply] = useOptimistic(
    effective,
    (current, change: Change) => {
      const on = change.granted ?? defaults.includes(change.permission);

      return on
        ? [...new Set([...current, change.permission])]
        : current.filter((key) => key !== change.permission);
    },
  );

  const save = useAction(setPermissionOverride, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const change = (permission: string, next: boolean | null) => {
    startTransition(async () => {
      apply({ permission, granted: next });
      await save.run({ roleId, permission, granted: next });
    });
  };

  const needle = search.trim().toLowerCase();

  const groups = groupKeys(
    needle === "" ? keys : keys.filter((key) => key.includes(needle)),
  );

  return (
    <div className="flex flex-col gap-4" data-testid="permission-matrix">
      <Input
        id={searchId}
        type="search"
        className="w-64"
        value={search}
        placeholder={t("Search permissions")}
        aria-label={t("Search permissions")}
        onChange={(event) => {
          setSearch(event.target.value);
        }}
      />
      {groups.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>{t("No permissions match")}</EmptyTitle>
            <EmptyDescription>{t("Try another key.")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setSearch("");
              }}
            >
              {t("Clear search")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="flex flex-col gap-6">
          {groups.map(([group, groupKeys]) => (
            <section key={group} className="flex flex-col gap-1">
              <h3 className="text-xs font-medium text-muted-foreground uppercase">
                {group}
              </h3>
              <ul className="flex flex-col divide-y">
                {groupKeys.map((key) => {
                  const on = granted.includes(key);
                  const byDefault = defaults.includes(key);
                  const overridden = on !== byDefault;
                  const canChange = editable && holds(held, key);

                  return (
                    <li
                      key={key}
                      className="flex items-center justify-between gap-3 py-2"
                    >
                      <div className="flex min-w-0 items-center gap-2">
                        <code className="truncate text-sm">{key}</code>
                        {overridden ? (
                          <Badge
                            variant={on ? "success-light" : "warning-light"}
                          >
                            {on ? t("Granted here") : t("Denied here")}
                          </Badge>
                        ) : null}
                      </div>
                      <div className="flex items-center gap-2">
                        {overridden && canChange ? (
                          <Button
                            size="icon-sm"
                            variant="ghost"
                            aria-label={t("Reset {key} to the default", {
                              key,
                            })}
                            onClick={() => {
                              change(key, null);
                            }}
                          >
                            <RotateCcwIcon />
                          </Button>
                        ) : null}
                        <Switch
                          checked={on}
                          disabled={!canChange}
                          aria-label={key}
                          onCheckedChange={(checked) => {
                            change(key, checked === byDefault ? null : checked);
                          }}
                        />
                      </div>
                    </li>
                  );
                })}
              </ul>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
