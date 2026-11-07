import { tenantOf } from "better-supabase/next";
import { forbidden, notFound } from "next/navigation";

import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { RuleBuilder } from "./rule-builder";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Render inside `<Suspense>`: reads the `rule` param, `new` for a new rule. */
export async function RuleEditor({ rule }: { rule: string }) {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const tenant = tenantOf(session);

  if (rule !== "new" && !UUID.test(rule)) {
    notFound();
  }

  if (!tenant || !can(permissions, "automations.read")) {
    forbidden();
  }

  const canEdit = can(permissions, "automations.write");

  if (rule === "new" && !canEdit) {
    forbidden();
  }

  return (
    <RuleBuilder
      key={rule}
      organizationId={tenant}
      rule={rule === "new" ? null : rule}
      canEdit={canEdit}
      canPublish={can(permissions, "automations.publish")}
    />
  );
}

export function RuleEditorSkeleton() {
  return (
    <Card aria-busy="true">
      <CardHeader>
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-4 w-72" />
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        <Skeleton className="h-9 w-full" />
        <div className="flex flex-col gap-2">
          {[0, 1, 2].map((row) => (
            <Skeleton key={row} className="h-8 w-full" />
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
