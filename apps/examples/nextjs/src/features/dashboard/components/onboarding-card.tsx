// #region recipe:onboarding-checklist
"use client";

import { useOnboarding } from "better-supabase/blocks/onboarding/react";
import { tenantOf } from "better-supabase/react";
import { CheckCircle2Icon, CircleIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { gettingStarted } from "@/features/onboarding/checklist";
import { Link } from "@/i18n/navigation";
import { useAuth } from "@/lib/hooks";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/** The API schema `gen` wrote for the onboarding block. */
const API_SCHEMA = blockConfig.onboarding.api;

/** The organization's getting-started checklist; hidden once every step is done. */
export function OnboardingCard() {
  const t = useExtracted("dashboard");
  const organizationId = tenantOf(useAuth()) ?? null;
  const { progress } = useOnboarding(gettingStarted, {
    organizationId,
    schema: API_SCHEMA,
  });
  if (!organizationId) return null;
  if (progress === undefined) return <OnboardingCardSkeleton />;
  if (progress.done) return null;
  const titles = {
    customer: t("Add your first customer"),
    invite: t("Invite a teammate"),
    "api-key": t("Create an API key"),
    plan: t("Review your plan"),
  };
  return (
    <Card data-testid="onboarding">
      <CardHeader>
        <CardTitle>{t("Get started")}</CardTitle>
        <CardDescription>
          {t("{completed, number} of {total, number} steps done", {
            completed: progress.completed,
            total: progress.total,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <Progress value={(progress.completed / progress.total) * 100} />
        <ul className="divide-y">
          {progress.steps.map((step) => (
            <li key={step.id} className="flex items-center gap-3 py-2">
              {step.completed ? (
                <CheckCircle2Icon className="size-4 text-primary" />
              ) : (
                <CircleIcon className="size-4 text-muted-foreground" />
              )}
              <span
                className={
                  step.completed
                    ? "flex-1 text-muted-foreground line-through"
                    : "flex-1"
                }
              >
                {titles[step.id]}
              </span>
              {step.completed ? null : (
                <Link
                  href={step.href ?? "/"}
                  className={buttonVariants({ variant: "outline", size: "sm" })}
                >
                  {t("Start")}
                </Link>
              )}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

export function OnboardingCardSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:onboarding-checklist
