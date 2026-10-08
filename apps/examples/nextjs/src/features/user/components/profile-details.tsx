import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getUserSettings } from "@/features/settings/settings-queries";

import { getPermissionSnapshot } from "../permission-snapshot";
import { roleOf } from "../user-permissions";
import { getMyProfile, getSession } from "../user-queries";
import { AvatarForm } from "./avatar-form";
import { ProfileForm } from "./profile-form";
import { RoleBadge } from "./role-badge";
import { WeeklyDigestSwitch } from "./weekly-digest-switch";

/** Render inside `<Suspense>`; the fallback is `ProfileDetailsSkeleton`. */
export async function ProfileDetails() {
  const [session, profile, snapshot, settings, t, format] = await Promise.all([
    getSession(),
    getMyProfile(),
    getPermissionSnapshot(),
    getUserSettings(),
    getExtracted("user"),
    getFormatter(),
  ]);
  if (session.kind !== "user") return null;
  const role = roleOf(session);
  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>{t("Profile")}</CardTitle>
          <CardDescription>{t("How your teammates see you.")}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <AvatarForm
            avatarUrl={profile?.avatarUrl ?? null}
            name={profile?.fullName ?? null}
            email={session.user.email ?? null}
          />
          <ProfileForm
            fullName={profile?.fullName ?? null}
            email={session.user.email ?? null}
          />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Preferences")}</CardTitle>
        </CardHeader>
        <CardContent>
          <WeeklyDigestSwitch enabled={settings.weeklyDigest} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Access")}</CardTitle>
          <CardDescription>
            {t(
              "From the memberships claim in your access token, for the active organization.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 text-sm sm:grid-cols-4">
            <dt className="text-muted-foreground">{t("Role")}</dt>
            <dd className="sm:col-span-3" data-testid="profile-role">
              {role ? <RoleBadge role={role} /> : t("No role")}
            </dd>
            <dt className="text-muted-foreground">{t("Permissions")}</dt>
            <dd
              className="flex flex-wrap gap-1 sm:col-span-3"
              data-testid="permissions"
            >
              {snapshot.permissions.length === 0
                ? t("None")
                : snapshot.permissions.map((permission) => (
                    <Badge
                      key={permission}
                      variant="outline"
                      className="font-mono"
                    >
                      {permission}
                    </Badge>
                  ))}
            </dd>
            <dt className="text-muted-foreground">{t("Token expires")}</dt>
            <dd className="tabular-nums sm:col-span-3">
              {session.expiresAt === null
                ? t("Unknown")
                : format.dateTime(new Date(session.expiresAt * 1000), {
                    dateStyle: "medium",
                    timeStyle: "medium",
                  })}
            </dd>
          </dl>
        </CardContent>
      </Card>
    </>
  );
}

export function ProfileDetailsSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <Skeleton className="h-64 rounded-xl" />
      <Skeleton className="h-28 rounded-xl" />
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
