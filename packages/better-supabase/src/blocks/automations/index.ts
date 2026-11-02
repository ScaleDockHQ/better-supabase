export {
  createRuleDispatcher,
  createAutomations,
  createRuleSink,
  createAutomationsAdmin,
  evaluateRule,
  eventTarget,
  ruleOf,
  ruleRecordFields,
  type Rule,
  type RuleAction,
  type RuleActionOutcome,
  type RuleDispatcher,
  type RuleDispatcherOptions,
  type RuleEvaluationEntry,
  type RuleInput,
  type RuleListOptions,
  type RuleMatch,
  type RuleRun,
  type Automations,
  type AutomationsAdmin,
  type RulesAdminOptions,
  type RuleSinkEvent,
  type RuleSinkOptions,
  type RuleSinkTarget,
  type AutomationsOptions,
  type RuleSubject,
  type RuleVersion,
} from "./automations.ts";

export {
  checkRuleConditions,
  defineRuleFields,
  RULE_LIMITS,
  ruleFilterFieldInfo,
  ruleFilterFields,
  type RuleField,
  type RuleFieldCatalog,
  type RuleFieldDefinition,
} from "./fields.ts";

export {
  createRuleBuilderController,
  type RuleBuilderActions,
  type RuleBuilderController,
  type RuleBuilderControllerOptions,
  type RuleBuilderSnapshot,
} from "./client.ts";

export {
  contains,
  emptyConditions,
  findNode,
  insertNode,
  moveNode,
  parentOf,
  removeNode,
  ruleOperators,
  setCombinator,
  setRuleField,
  setRuleOperator,
  updateNode,
} from "./tree.ts";

export {
  type ActionManifest,
  approvalsAction,
  blockActions,
  notifyAction,
  type RuleApprovals,
  type RuleFieldSetter,
  type RuleFieldWrite,
  type RuleNotifier,
  type RuleSubjectContext,
  type RuleWebhooks,
  type RuleWorkflows,
  setFieldAction,
  webhookAction,
  workflowAction,
} from "./actions.ts";

export {
  defineConversionAction,
  narrowClients,
  type ConversionClients,
  type ConversionContext,
  type ConversionOutcome,
  type ConversionRef,
  type ConversionRelations,
  type ConversionSpec,
} from "./conversion.ts";

export {
  actionKey,
  createActionRegistry,
  defineAction,
  type Action,
  type ActionCall,
  type ActionContext,
  type ActionDescriptor,
  type ActionHandler,
  type ActionInfo,
  type ActionOrigin,
  type ActionRef,
  type ActionRegistry,
  type ActionSpec,
  type DefaultAutomation,
} from "../../core/automation.ts";

export {
  automationsEvents,
  type RuleEventData,
  type RuleMatchedEventData,
  type AutomationsEvents,
} from "./events.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { automationsBlock } from "./manifest.ts";
