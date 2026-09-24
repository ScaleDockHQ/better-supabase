import { createMcp } from 'better-supabase/mcp';

import { sb } from '../_shared/supabase.ts';

export const mcp = createMcp(sb, {
  name: 'crm',
  version: '0.1.0',
  resources: {
    customers: { select: ['id', 'name', 'status', 'organizationId'] },
    tags: { select: ['id', 'name', 'organizationId'] },
  },
});
