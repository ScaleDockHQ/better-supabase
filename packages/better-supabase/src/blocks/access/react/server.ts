import type {
  Can as ClientCan,
  usePermission as useClientPermission,
  usePermissions as useClientPermissions,
} from "./index.ts";

export type {
  CanProps,
  PermissionSet,
  PermissionsState,
  UsePermissionsOptions,
} from "./index.ts";

const clientOnly = (name: string): Error =>
  new Error(
    `better-supabase: ${name} runs in Client Components only. In Server Components call \`bs.blocks.client(db, "access").permissions(keys)\` and \`can(set, key)\` from \`better-supabase/blocks/access\` instead.`,
  );

/** The `react-server` build of `usePermissions`. */
export const usePermissions: typeof useClientPermissions = () => {
  throw clientOnly("usePermissions()");
};

/** The `react-server` build of `usePermission`. */
export const usePermission: typeof useClientPermission = () => {
  throw clientOnly("usePermission()");
};

/** The `react-server` build of `<Can>`. */
export const Can: typeof ClientCan = () => {
  throw clientOnly("<Can>");
};
