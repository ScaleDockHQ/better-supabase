"use client";

import { useAction } from "better-supabase/react";
import { UserPlusIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import type { SharingGrant, SharingTarget } from "../drive-grants-actions";

import {
  loadDriveSharing,
  shareDriveItem,
  unshareDriveItem,
} from "../drive-grants-actions";
import { DRIVE_ROLES, type DriveRole } from "../drive-roles";

const isRole = (value: unknown): value is DriveRole =>
  DRIVE_ROLES.some((role) => role === value);

function useRoleLabel() {
  const t = useExtracted("drive");

  return (role: string): string => {
    switch (role) {
      case "viewer": {
        return t("Can view");
      }

      case "editor": {
        return t("Can edit");
      }

      case "owner": {
        return t("Owner");
      }

      default: {
        return role;
      }
    }
  };
}

const keyOf = (target: { type: string; id: string }) =>
  `${target.type}:${target.id}`;

// #region recipe:grants-editor
/** Loads an item's grants; `open` starts a fresh read, so call it with the dialog. */
export function useDriveSharing(id: string) {
  const load = useAction(loadDriveSharing);

  return {
    ...load,
    open: () => {
      load.reset();
      void load.run({ id });
    },
  };
}

/**
 * Who can open a drive item: its grants, inherited ones from the folders
 * above included, and a picker to share it with a member or a team.
 */
export function GrantsEditor({
  id,
  name,
  load,
  open,
  onOpenChange,
}: {
  id: string;
  name: string;
  load: ReturnType<typeof useDriveSharing>;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const t = useExtracted("drive");
  const errorMessage = useErrorMessage();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent data-recipe="grants-editor">
        <DialogHeader>
          <DialogTitle>{t("Share {name}", { name })}</DialogTitle>
          <DialogDescription>
            {t("Members and teams you add here can open it.")}
          </DialogDescription>
        </DialogHeader>
        {load.error ? (
          <div
            role="alert"
            className="flex items-center justify-between gap-2 text-sm text-destructive"
          >
            {errorMessage(load.error)}
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                void load.run({ id });
              }}
            >
              {t("Retry")}
            </Button>
          </div>
        ) : load.data === undefined ? (
          <div className="flex flex-col gap-2" aria-busy="true">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
          </div>
        ) : (
          <SharingPanel
            id={id}
            grants={load.data.grants}
            targets={load.data.targets}
            onChange={() => {
              void load.run({ id });
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function SharingPanel({
  id,
  grants,
  targets,
  onChange,
}: {
  id: string;
  grants: readonly SharingGrant[];
  targets: readonly SharingTarget[];
  onChange: () => void;
}) {
  const t = useExtracted("drive");
  const fieldId = useId();
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const share = useAction(shareDriveItem, { onSuccess: onChange, onError });
  const unshare = useAction(unshareDriveItem, { onSuccess: onChange, onError });

  const granted = new Set(grants.map(keyOf));

  const options = targets
    .filter((target) => !granted.has(keyOf(target)))
    .map((target) => ({
      value: keyOf(target),
      label:
        target.type === "team"
          ? t("{name} (team)", { name: target.name })
          : target.name,
    }));

  const [picked, setPicked] = useState<string | null>(null);
  const [role, setRole] = useState<DriveRole>("viewer");

  const target = targets.find(
    (each) => keyOf(each) === (picked ?? options[0]?.value),
  );

  return (
    <div className="flex flex-col gap-4">
      {grants.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t("Not shared yet. Pick a member or team below.")}
        </p>
      ) : (
        <ul className="flex flex-col gap-2">
          {grants.map((grant) => (
            <li
              key={`${keyOf(grant)}:${grant.inherited ? "up" : "here"}`}
              className="flex items-center justify-between gap-2"
            >
              <div className="flex min-w-0 flex-col gap-1">
                <span className="truncate text-sm">{grant.name}</span>
                {grant.inherited ? (
                  <span className="text-xs text-muted-foreground">
                    {t("From a folder above")}
                  </span>
                ) : null}
              </div>
              <div className="flex items-center gap-2">
                <Badge variant="secondary">{roleLabel(grant.role)}</Badge>
                {!grant.inherited && grant.type !== "role" ? (
                  <Button
                    size="icon-sm"
                    variant="ghost"
                    disabled={unshare.pending}
                    aria-label={t("Stop sharing with {name}", {
                      name: grant.name,
                    })}
                    onClick={() => {
                      if (grant.type !== "role") {
                        void unshare.run({
                          id,
                          principal: { type: grant.type, id: grant.id },
                        });
                      }
                    }}
                  >
                    <XIcon />
                  </Button>
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}
      {target === undefined ? null : (
        <form
          className="flex items-end gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            void share.run({
              id,
              principal: { type: target.type, id: target.id },
              role,
            });
            setPicked(null);
          }}
        >
          <Field className="min-w-0 flex-1">
            <FieldLabel htmlFor={`${fieldId}-target`}>
              {t("Share with")}
            </FieldLabel>
            <Select
              value={keyOf(target)}
              items={options}
              onValueChange={(value) => {
                const match = options.find((option) => option.value === value);

                if (match) {
                  setPicked(match.value);
                }
              }}
            >
              <SelectTrigger id={`${fieldId}-target`} className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {options.map((option) => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Field className="w-36">
            <FieldLabel htmlFor={`${fieldId}-role`}>{t("Access")}</FieldLabel>
            <Select
              value={role}
              items={DRIVE_ROLES.map((each) => ({
                value: each,
                label: roleLabel(each),
              }))}
              onValueChange={(value) => {
                if (isRole(value)) {
                  setRole(value);
                }
              }}
            >
              <SelectTrigger id={`${fieldId}-role`} className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {DRIVE_ROLES.map((each) => (
                  <SelectItem key={each} value={each}>
                    {roleLabel(each)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Button type="submit" disabled={share.pending}>
            <UserPlusIcon />
            {t("Share")}
          </Button>
        </form>
      )}
    </div>
  );
}
// #endregion recipe:grants-editor
