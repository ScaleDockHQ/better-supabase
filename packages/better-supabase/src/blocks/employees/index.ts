export {
  type Contract,
  type ContractInput,
  createEmployees,
  type EmergencyContact,
  type Employee,
  type EmployeeChange,
  type EmployeeChangeResult,
  type EmployeeField,
  type EmployeeInput,
  type Employees,
  employeesSubjects,
  type EmployeesOptions,
  type EmployeeStatus,
  type OrgChartEntry,
  type PrivateDetails,
  type PrivateDetailsInput,
  type SalaryPeriod,
} from "./employees.ts";

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

export { employeesBlock } from "./manifest.ts";

export { employeesEvents } from "./events.ts";

export type { EmployeesEvents } from "./events.ts";
