"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useRouter } from "@/i18n/navigation";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { createFromTemplate } from "../builder-actions";
import { workflowTemplates } from "../workflow-templates";

/**
 * The template cards: each one makes a draft definition and opens it in the
 * editor.
 */
export function TemplateGallery() {
  const t = useExtracted("workflows");
  const router = useRouter();
  const errorMessage = useErrorMessage();

  const create = useAction(createFromTemplate, {
    onSuccess: (id) => {
      router.push(`/workflows/builder/${id}`);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <div
      className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3"
      data-testid="template-gallery"
    >
      {workflowTemplates.map((template) => (
        <Card key={template.id} data-template={template.id}>
          <CardHeader>
            <CardTitle>{template.name}</CardTitle>
            <CardDescription>{template.description}</CardDescription>
            <CardAction>
              <Button
                size="sm"
                disabled={create.pending}
                onClick={() => {
                  void create.run({ template: template.id });
                }}
              >
                {t("Use template")}
              </Button>
            </CardAction>
          </CardHeader>
          <CardContent className="flex flex-wrap items-center gap-2">
            {template.tags.map((tag) => (
              <Badge key={tag} variant="outline">
                {tag}
              </Badge>
            ))}
            <span className="text-xs text-muted-foreground tabular-nums">
              {t("{count} nodes", {
                count: String(template.graph.nodes.length),
              })}
            </span>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
