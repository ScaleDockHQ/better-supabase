"use client";

import { useActionForm } from "better-supabase/react";
import { UsersIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { usePathname, useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type { TeamOption } from "../work-types";

import { createTeam } from "../work-actions";

const ALL_TEAMS = "";

// #region recipe:team-picker
/**
 * Scopes the page to one of the organization's teams through `?team=`. With no
 * teams yet, it offers to create one when the caller holds `teams.manage`.
 */
export function TeamPicker({
  teams,
  teamId,
  canManage,
}: {
  teams: readonly TeamOption[];
  teamId: string | null;
  canManage: boolean;
}) {
  const t = useExtracted("work");
  const fieldId = useId();
  const router = useRouter();
  const pathname = usePathname();
  const errorMessage = useErrorMessage();
  const [switching, startTransition] = useTransition();

  const form = useActionForm(createTeam, {
    onSuccess: () => {
      toast.success(t("Team created"));
    },
  });

  if (teams.length === 0) {
    const error = form.error === undefined ? null : errorMessage(form.error);

    return (
      <Empty className="border" data-recipe="team-picker">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <UsersIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No teams yet")}</EmptyTitle>
          <EmptyDescription>
            {canManage
              ? t("Create a team to group work and filter the board by it.")
              : t("An admin can create teams to group work.")}
          </EmptyDescription>
        </EmptyHeader>
        {canManage ? (
          <EmptyContent>
            <form {...form.formProps} className="flex w-full items-end gap-2">
              <Field data-invalid={error ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-team-name`}>
                  {t("Team name")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-team-name`}
                  name="name"
                  required
                  maxLength={80}
                  autoComplete="off"
                />
                {error ? <FieldError>{error}</FieldError> : null}
              </Field>
              <Button type="submit" disabled={form.pending}>
                {t("Create team")}
              </Button>
            </form>
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

  const items = [
    { value: ALL_TEAMS, label: t("All teams") },
    ...teams.map((team) => ({ value: team.id, label: team.name })),
  ];

  return (
    <div className="flex items-center gap-2" data-recipe="team-picker">
      <span className="text-sm text-muted-foreground" id={`${fieldId}-label`}>
        {t("Team")}
      </span>
      <Select
        value={teamId ?? ALL_TEAMS}
        items={items}
        disabled={switching}
        onValueChange={(value) => {
          const next = value ?? ALL_TEAMS;

          startTransition(() => {
            router.replace(
              next === ALL_TEAMS
                ? pathname
                : `${pathname}?team=${encodeURIComponent(next)}`,
            );
          });
        }}
      >
        <SelectTrigger className="w-48" aria-labelledby={`${fieldId}-label`}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {items.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
// #endregion recipe:team-picker
