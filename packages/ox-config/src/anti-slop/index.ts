import { type Plugin, eslintCompatPlugin } from '@oxlint/plugins';

import { noChainedTypeAssertionsRule } from './rules/no-chained-type-assertions.ts';
import { noModuleMockingRule } from './rules/no-module-mocking.ts';
import { noReflectApplyRule } from './rules/no-reflect-apply.ts';
import { noReflectGetRule } from './rules/no-reflect-get.ts';
import { noWidenThenAssertRule } from './rules/no-widen-then-assert.ts';
import { requireSafetyCommentForTypeAssertionRule } from './rules/require-safety-comment-for-type-assertion.ts';

/**
 * Oxlint rules that reject low-evidence type and test patterns. Only the
 * rules that fit a published library are included.
 */
const antiSlopPlugin: Plugin = eslintCompatPlugin({
  meta: { name: 'anti-slop' },
  rules: {
    'no-chained-type-assertions': noChainedTypeAssertionsRule,
    'no-module-mocking': noModuleMockingRule,
    'no-reflect-apply': noReflectApplyRule,
    'no-reflect-get': noReflectGetRule,
    'no-widen-then-assert': noWidenThenAssertRule,
    'require-safety-comment-for-type-assertion':
      requireSafetyCommentForTypeAssertionRule,
  },
});

export default antiSlopPlugin;
