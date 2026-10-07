"use client";

import { useTheme } from "@wrksz/themes/client";
import {
  ChevronsUpDownIcon,
  LanguagesIcon,
  LogOutIcon,
  MonitorIcon,
  MoonIcon,
  ShieldCheckIcon,
  SunIcon,
  UserIcon,
} from "lucide-react";
import { useExtracted, useLocale } from "next-intl";
import { useTransition } from "react";

import type { Role } from "@/lib/claims";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { SidebarMenuButton } from "@/components/ui/sidebar";
import { useRoleLabel } from "@/features/organization/use-role-label";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { type Locale, routing } from "@/i18n/routing";
import { useSupabase } from "@/lib/hooks";
import { initials } from "@/lib/initials";

import { sessionChanged } from "../user-actions";

const LOCALE_NAMES = {
  en: "English",
  nl: "Nederlands",
} satisfies Record<Locale, string>;

function isLocale(value: string): value is Locale {
  return routing.locales.some((locale) => locale === value);
}

export function UserMenuDropdown({
  name,
  email,
  avatarUrl,
  role,
}: {
  name: string | null;
  email: string | null;
  avatarUrl: string | null;
  role: Role | null;
}) {
  const t = useExtracted("user");
  const roleLabel = useRoleLabel();
  const { theme, setTheme } = useTheme();
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();
  const supabase = useSupabase();
  const [pending, startTransition] = useTransition();

  const avatar = (
    <Avatar className="size-8 rounded-lg">
      {avatarUrl ? <AvatarImage src={avatarUrl} alt="" /> : null}
      <AvatarFallback className="rounded-lg">
        {initials(name, email)}
      </AvatarFallback>
    </Avatar>
  );
  const identity = (
    <div className="grid flex-1 text-left text-sm leading-tight">
      <span className="truncate font-medium">{name ?? email}</span>
      <span
        className="text-muted-foreground truncate text-xs"
        data-testid="role"
      >
        {role ? roleLabel(role) : t("No role")}
      </span>
    </div>
  );

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <SidebarMenuButton
            size="lg"
            className="data-popup-open:bg-sidebar-accent"
            aria-label={t("Account menu")}
          />
        }
      >
        {avatar}
        {identity}
        <ChevronsUpDownIcon className="ml-auto size-4" />
      </DropdownMenuTrigger>
      <DropdownMenuContent className="w-60" side="right" align="end">
        <DropdownMenuGroup>
          <DropdownMenuLabel className="flex items-center gap-2 font-normal">
            {avatar}
            <div className="grid flex-1 text-sm leading-tight">
              <span className="text-foreground truncate font-medium">
                {name ?? email}
              </span>
              <span className="truncate text-xs">{email}</span>
            </div>
          </DropdownMenuLabel>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuItem render={<Link href="/settings/profile" />}>
            <UserIcon />
            {t("Profile")}
          </DropdownMenuItem>
          <DropdownMenuItem render={<Link href="/settings/security" />}>
            <ShieldCheckIcon />
            {t("Security")}
          </DropdownMenuItem>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuSub>
            <DropdownMenuSubTrigger>
              <SunIcon />
              {t("Theme")}
            </DropdownMenuSubTrigger>
            <DropdownMenuSubContent>
              <DropdownMenuRadioGroup
                value={theme ?? "system"}
                onValueChange={(value: string) => {
                  if (
                    value === "light" ||
                    value === "dark" ||
                    value === "system"
                  ) {
                    setTheme(value);
                  }
                }}
              >
                <DropdownMenuRadioItem value="light">
                  <SunIcon />
                  {t("Light")}
                </DropdownMenuRadioItem>
                <DropdownMenuRadioItem value="dark">
                  <MoonIcon />
                  {t("Dark")}
                </DropdownMenuRadioItem>
                <DropdownMenuRadioItem value="system">
                  <MonitorIcon />
                  {t("System")}
                </DropdownMenuRadioItem>
              </DropdownMenuRadioGroup>
            </DropdownMenuSubContent>
          </DropdownMenuSub>
          <DropdownMenuSub>
            <DropdownMenuSubTrigger>
              <LanguagesIcon />
              {t("Language")}
            </DropdownMenuSubTrigger>
            <DropdownMenuSubContent>
              <DropdownMenuRadioGroup
                value={locale}
                onValueChange={(value: string) => {
                  if (!isLocale(value)) return;
                  startTransition(() => {
                    router.replace(pathname, { locale: value });
                  });
                }}
              >
                {routing.locales.map((option) => (
                  <DropdownMenuRadioItem
                    key={option}
                    value={option}
                    lang={option}
                  >
                    {LOCALE_NAMES[option]}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuSubContent>
          </DropdownMenuSub>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          disabled={pending}
          onClick={() => {
            startTransition(async () => {
              await supabase.auth.signOut();
              await sessionChanged();
              router.push("/login");
            });
          }}
        >
          <LogOutIcon />
          {t("Sign out")}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
