import { CheckCircle2Icon, CircleIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

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
import { activeOrganizationId } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { type OnboardingStepId, getOnboarding } from "../dashboard-queries";

/** Render inside `<Suspense>`; hidden once every step is done. */
export async function OnboardingCard() {
  const [session, t] = await Promise.all([
    getSession(),
    getExtracted("dashboard"),
  ]);
  const organizationId = activeOrganizationId(session);
  if (!organizationId) return null;
  const progress = await getOnboarding(organizationId);
  if (progress.done) return null;
  const titles = {
    customer: t("Add your first customer"),
    invite: t("Invite a teammate"),
    "api-key": t("Create an API key"),
    plan: t("Review your plan"),
  } satisfies Record<OnboardingStepId, string>;
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
                <CheckCircle2Icon className="text-primary size-4" />
              ) : (
                <CircleIcon className="text-muted-foreground size-4" />
              )}
              <span
                className={
                  step.completed
                    ? "text-muted-foreground flex-1 line-through"
                    : "flex-1"
                }
              >
                {titles[step.id]}
              </span>
              {step.completed ? null : (
                <Link
                  href={step.href}
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
