import { useExtracted } from "next-intl";
import { Suspense } from "react";

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarInset,
  SidebarProvider,
  SidebarRail,
} from "@/components/ui/sidebar";
import { Announcements } from "@/features/announcements/components/announcements";
import { AppHeader } from "@/features/navigation/components/app-header";
import { AppNav } from "@/features/navigation/components/app-nav";
import { SideNavSkeleton } from "@/features/navigation/components/side-nav";
import {
  OrganizationSwitcher,
  OrganizationSwitcherSkeleton,
} from "@/features/organization/components/organization-switcher";
import { ImpersonationBanner } from "@/features/user/components/impersonation-banner";
import {
  UserMenu,
  UserMenuSkeleton,
} from "@/features/user/components/user-menu";

/**
 * Synchronous on purpose: the sidebar frame, header and skeletons are the
 * static shell. The sidebar starts open instead of reading its cookie, which
 * would make every page dynamic. Everything that reads the session streams
 * in behind its own `<Suspense>` boundary.
 */
export default function AppLayout({ children }: LayoutProps<"/[locale]">) {
  const t = useExtracted("navigation");
  const toggle = t("Toggle sidebar");
  return (
    <SidebarProvider>
      <Sidebar collapsible="icon">
        <SidebarHeader>
          <Suspense fallback={<OrganizationSwitcherSkeleton />}>
            <OrganizationSwitcher />
          </Suspense>
        </SidebarHeader>
        <SidebarContent>
          <Suspense fallback={<SideNavSkeleton />}>
            <AppNav />
          </Suspense>
        </SidebarContent>
        <SidebarFooter>
          <Suspense fallback={<UserMenuSkeleton />}>
            <UserMenu />
          </Suspense>
        </SidebarFooter>
        <SidebarRail aria-label={toggle} title={toggle} />
      </Sidebar>
      <SidebarInset>
        <AppHeader />
        <div className="flex flex-1 flex-col gap-6 p-4 md:p-6">
          <Suspense fallback={null}>
            <ImpersonationBanner />
          </Suspense>
          <Suspense fallback={null}>
            <Announcements />
          </Suspense>
          {children}
        </div>
      </SidebarInset>
    </SidebarProvider>
  );
}
