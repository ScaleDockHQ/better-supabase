import type { Permission } from '@/features/user/user-permissions';

export interface NavItem {
  readonly href: string;
  readonly label: string;
  /** Hidden from the menu (and redirected by the proxy) without it. */
  readonly requires?: Permission;
}

export const navItems: readonly NavItem[] = [
  { href: '/', label: 'Dashboard' },
  { href: '/customers', label: 'Customers', requires: 'customers.read' },
  { href: '/inbox', label: 'Inbox' },
  { href: '/calendar', label: 'Calendar' },
  { href: '/profile', label: 'Profile' },
  { href: '/reports', label: 'Reports', requires: 'reports.read' },
  { href: '/users', label: 'Users', requires: 'users.manage' },
  { href: '/billing', label: 'Billing', requires: 'billing.manage' },
  { href: '/audit', label: 'Audit log', requires: 'audit.read' },
  { href: '/settings', label: 'Settings', requires: 'settings.manage' },
];

/** The permission a path needs, from the menu entry it belongs to. */
export function requiredPermission(pathname: string): Permission | undefined {
  return navItems.find(
    (item) =>
      item.href !== '/' &&
      (pathname === item.href || pathname.startsWith(`${item.href}/`)),
  )?.requires;
}
