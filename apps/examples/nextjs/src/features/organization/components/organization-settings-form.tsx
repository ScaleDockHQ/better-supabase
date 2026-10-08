"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import { updateOrganizationSettings } from "../organization-actions";
import { useRoleLabel } from "../use-role-label";

export function OrganizationSettingsForm({
  defaultRole,
  weekStart,
  canEdit,
}: {
  defaultRole: "member" | "admin";
  weekStart: "monday" | "sunday";
  canEdit: boolean;
}) {
  const t = useExtracted("organization");
  const fieldId = useId();
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const form = useActionForm(updateOrganizationSettings, {
    resetOnSuccess: false,
    onSuccess: () => {
      toast.success(t("Settings saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  const roles = [
    { value: "member", label: roleLabel("member") },
    { value: "admin", label: roleLabel("admin") },
  ];
  const days = [
    { value: "monday", label: t("Monday") },
    { value: "sunday", label: t("Sunday") },
  ];
  return (
    <form {...form.formProps} className="space-y-6">
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor={`${fieldId}-default-role`}>
            {t("Default role for invitations")}
          </FieldLabel>
          <Select
            name="defaultRole"
            defaultValue={defaultRole}
            items={roles}
            disabled={!canEdit}
          >
            <SelectTrigger id={`${fieldId}-default-role`} className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {roles.map((role) => (
                <SelectItem key={role.value} value={role.value}>
                  {role.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field>
          <FieldLabel htmlFor={`${fieldId}-week-start`}>
            {t("Week starts on")}
          </FieldLabel>
          <Select
            name="weekStart"
            defaultValue={weekStart}
            items={days}
            disabled={!canEdit}
          >
            <SelectTrigger id={`${fieldId}-week-start`} className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {days.map((day) => (
                <SelectItem key={day.value} value={day.value}>
                  {day.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <FieldDescription>
            {t("Stored per organization by the settings module.")}
          </FieldDescription>
        </Field>
      </FieldGroup>
      {canEdit ? (
        <Button type="submit" variant="outline" disabled={form.pending}>
          {t("Save settings")}
        </Button>
      ) : null}
    </form>
  );
}
