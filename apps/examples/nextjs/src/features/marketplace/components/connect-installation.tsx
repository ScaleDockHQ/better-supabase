"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { PlugIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { connectInstallation } from "../marketplace-actions";

/** Links a Vercel configuration id to the organization and lists its resources. */
export function ConnectInstallation() {
  const t = useExtracted("marketplace");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(connectInstallation);
  const error = form.error === undefined ? null : errorMessage(form.error);
  const view = form.data;

  return (
    <div className="grid gap-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("Installation")}</CardTitle>
          <CardDescription>
            {t(
              "Enter the configuration id Vercel shows for the installation. The organization is linked to it, and its resources are listed below.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form {...form.formProps} className="flex items-end gap-2">
            <Field data-invalid={error ? true : undefined} className="flex-1">
              <FieldLabel htmlFor={`${fieldId}-configuration`}>
                {t("Configuration id")}
              </FieldLabel>
              <Input
                id={`${fieldId}-configuration`}
                name="configurationId"
                required
                autoComplete="off"
                placeholder="icfg_..."
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Button type="submit" disabled={form.pending}>
              {t("Connect")}
            </Button>
          </form>
        </CardContent>
      </Card>
      {view === undefined ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <PlugIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No installation connected")}</EmptyTitle>
            <EmptyDescription>
              {t(
                "Install the app from the Vercel Marketplace, then connect its configuration here.",
              )}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>{view.configurationId}</CardTitle>
            <CardDescription>
              <Badge
                variant={
                  view.status === "active" ? "success-light" : "secondary"
                }
              >
                {view.status}
              </Badge>
            </CardDescription>
          </CardHeader>
          <CardContent>
            {view.resources.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t("No resources provisioned yet.")}
              </p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("Resource")}</TableHead>
                    <TableHead>{t("Plan")}</TableHead>
                    <TableHead>{t("Status")}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {view.resources.map((resource) => (
                    <TableRow key={resource.externalId}>
                      <TableCell className="font-medium">
                        {resource.name}
                      </TableCell>
                      <TableCell>{resource.planId ?? "-"}</TableCell>
                      <TableCell>
                        <Badge
                          variant={
                            resource.status === "ready"
                              ? "success-light"
                              : "secondary"
                          }
                        >
                          {resource.status}
                        </Badge>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
