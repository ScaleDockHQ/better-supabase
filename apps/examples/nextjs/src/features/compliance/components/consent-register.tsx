import type { LegalBasis } from "better-supabase/blocks/consents";

import { FileCheckIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getPurposes } from "../compliance-queries";

// #region recipe:consent-register
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: the purposes the organization asks consent for,
 * with their lawful basis, version and how long a grant lasts.
 */
export async function ConsentRegister() {
  const [state, t] = await Promise.all([
    getPurposes(),
    getExtracted("compliance"),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  const basis = (legalBasis: LegalBasis) => {
    switch (legalBasis) {
      case "consent": {
        return t("Consent");
      }

      case "contract": {
        return t("Contract");
      }

      case "legal_obligation": {
        return t("Legal obligation");
      }

      case "vital_interest": {
        return t("Vital interest");
      }

      case "public_task": {
        return t("Public task");
      }

      case "legitimate_interest": {
        return t("Legitimate interest");
      }

      default: {
        const never: never = legalBasis;

        return String(never);
      }
    }
  };

  return (
    <Card data-recipe="consent-register">
      <CardHeader>
        <CardTitle>{t("Consent register")}</CardTitle>
        <CardDescription>
          {t(
            "What the organization asks consent for. A new version of a purpose asks every record again.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The consent purposes didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : state.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No consent purposes")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Save a purpose, such as marketing email, before recording consent on a record.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                href="https://bettersupabase.com/docs/blocks/consents"
                className={buttonVariants()}
              >
                {t("Read the consents guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Purpose")}</TableHead>
                <TableHead>{t("Lawful basis")}</TableHead>
                <TableHead>{t("Version")}</TableHead>
                <TableHead>{t("Lasts")}</TableHead>
                <TableHead>{t("Evidence")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {state.data.map((row) => (
                <TableRow key={row.id}>
                  <TableCell>
                    <div className="flex flex-col gap-1">
                      <span className="font-medium">{row.title}</span>
                      <span className="text-xs text-muted-foreground">
                        {row.key}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell>{basis(row.legalBasis)}</TableCell>
                  <TableCell className="tabular-nums">{row.version}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {row.validMonths === null
                      ? t("Until withdrawn")
                      : t("{months, number} months", {
                          months: row.validMonths,
                        })}
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {row.requiresSignature ? (
                        <Badge variant="info-light">{t("Signature")}</Badge>
                      ) : (
                        <Badge variant="secondary">{t("Any")}</Badge>
                      )}
                      {row.system ? (
                        <Badge variant="secondary">{t("System")}</Badge>
                      ) : null}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function ConsentRegisterSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:consent-register
