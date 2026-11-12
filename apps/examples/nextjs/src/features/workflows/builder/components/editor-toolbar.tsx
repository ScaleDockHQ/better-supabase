"use client";

import type { WorkflowGraph } from "better-supabase/blocks/workflow-editor";

import {
  KeyboardIcon,
  LayoutTemplateIcon,
  Redo2Icon,
  SaveIcon,
  Undo2Icon,
} from "lucide-react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { ButtonGroup } from "@/components/ui/button-group";
import { Kbd, KbdGroup } from "@/components/ui/kbd";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

import type { CredentialRow, TriggerRow } from "../builder-queries";

import { CredentialSheet } from "./credential-sheet";
import { PublishDialog } from "./publish-dialog";
import { TriggerSheet } from "./trigger-sheet";

/**
 * Undo and redo, layout, save, publish and the sheets for triggers and
 * credentials.
 */
export function EditorToolbar({
  definition,
  triggers,
  credentials,
  published,
  graph,
  errors,
  dirty,
  canUndo,
  canRedo,
  saving,
  publishing,
  onUndo,
  onRedo,
  onLayout,
  onSave,
  onPublish,
}: {
  definition: string;
  triggers: readonly TriggerRow[];
  credentials: readonly CredentialRow[];
  published: { readonly version: number; readonly graph: WorkflowGraph } | null;
  graph: WorkflowGraph;
  /** Problems that block publishing. */
  errors: number;
  dirty: boolean;
  canUndo: boolean;
  canRedo: boolean;
  saving: boolean;
  publishing: boolean;
  onUndo: () => void;
  onRedo: () => void;
  onLayout: () => void;
  onSave: () => void;
  onPublish: () => void;
}) {
  const t = useExtracted("workflows");

  const shortcuts = [
    [t("Undo"), ["⌘", "Z"]],
    [t("Redo"), ["⇧", "⌘", "Z"]],
    [t("Copy"), ["⌘", "C"]],
    [t("Paste"), ["⌘", "V"]],
    [t("Duplicate"), ["⌘", "D"]],
    [t("Delete"), ["⌫"]],
    [t("Save draft"), ["⌘", "S"]],
    [t("Auto layout"), ["⇧", "L"]],
  ] as const;

  return (
    <div className="flex flex-wrap items-center gap-2">
      <ButtonGroup>
        <Button
          variant="outline"
          size="sm"
          disabled={!canUndo}
          aria-label={t("Undo")}
          onClick={onUndo}
        >
          <Undo2Icon />
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={!canRedo}
          aria-label={t("Redo")}
          onClick={onRedo}
        >
          <Redo2Icon />
        </Button>
        <Button variant="outline" size="sm" onClick={onLayout}>
          <LayoutTemplateIcon />
          {t("Auto layout")}
        </Button>
      </ButtonGroup>
      <Popover>
        <PopoverTrigger
          render={
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label={t("Keyboard shortcuts")}
            />
          }
        >
          <KeyboardIcon />
        </PopoverTrigger>
        <PopoverContent align="start" className="w-64">
          <dl className="flex flex-col gap-2 text-sm">
            {shortcuts.map(([name, keys]) => (
              <div key={name} className="flex items-center justify-between">
                <dt>{name}</dt>
                <dd>
                  <KbdGroup>
                    {keys.map((key) => (
                      <Kbd key={key}>{key}</Kbd>
                    ))}
                  </KbdGroup>
                </dd>
              </div>
            ))}
          </dl>
        </PopoverContent>
      </Popover>
      <span className="grow" />
      {dirty ? (
        <Badge variant="warning-light">{t("Unsaved changes")}</Badge>
      ) : null}
      <TriggerSheet definition={definition} triggers={triggers} />
      <CredentialSheet credentials={credentials} />
      <Button variant="outline" size="sm" disabled={saving} onClick={onSave}>
        <SaveIcon />
        {t("Save draft")}
      </Button>
      <PublishDialog
        published={published}
        graph={graph}
        errors={errors}
        pending={publishing}
        onPublish={onPublish}
      />
    </div>
  );
}
