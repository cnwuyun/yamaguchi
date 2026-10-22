# 单 Agent 拆分为 Workflow 混合编排（Inventory Reservations）

## 1. 摘要

把 `RESERVATIONSWORKER_V10_YY` 这个单 Agent（一个 LLM 承载 7 个步骤 + 14 个工具）拆成一个 **`data_pipeline` 架构的 workflow**：确定性节点负责取数与写操作（BO_FUNCTION / TOOL / CODE），LLM 节点只负责意图与参数抽取、以及结果的自然语言呈现。原有 `.agent` 与单 agent `.wf` 均保留不动，新工作流单独建文件，便于对比与回退。

目标文件：`src/workflows/inventory_reservations_ai_assistant_workflow_agent_v1_yy.wf`
`workflowCode`：`INVENTORY_RESERVATIONS_AI_ASSISTANT_WORKFLOW_AGENT_V1_YY`
family/product：`SCM` / `INVENTORY_MANAGEMENT`（与环境内可选项一致）

## 2. 现状分析

### 2.1 单 Agent 现状

- 文件：[reservationsworker_v10_yy.agent](file:///c:/EEE/code/08_work/yamaguchi/src/agents/reservationsworker_v10_yy.agent)
- 会话规则：每次会话只调用一次 `GetUserSession`；按 `Language`/`Territory`/`TimeZone` 适配输出；`OrganizationCode`/`ItemNumber` 可选校验。
- 7 个业务流程步骤：
  1. 引导语（非 `CreateOrderReservation` 时）
  2. 参数映射（CustomerName LIKE、日期区间、DemandSourceType 仅 4 值、ReservationStatus 仅 3 值）
  3. Fetch Demand Documents（构造 `pFinder`/`pQuery`；Work order 走 `getall_WorkOrderDemandsInOtherOrgs`，其余走 `getall_invOrderReservationStatuses`）
  4. Fetch Document Lines（`getall_reservationsByDocumentLines`）
  5. Fetch Supply Sources（`getall_availableToReserveByDocumentTypes`）
  6. Fetch Supply Lines（`getall_supplyLineDetailsByTypes`）
  7. Create Reservations（auto / single，逐需求行创建；成功后生成 Manage Reservations 深链，缺 on-hand 时生成 Demand Documents 深链）
- 另有删除确认（Yes/Y 才执行）与“更新供给源”的特殊规则。

### 2.2 现有工作流现状

[inventory_reservations_ai_assistant_single_agent_v10_yy.wf](file:///c:/EEE/code/08_work/yamaguchi/src/workflows/inventory_reservations_ai_assistant_single_agent_v10_yy.wf) 的 `architecture` 为 `single_agent`，`dataPipeline` 只有 `end` 节点，靠 `agentsValueMappings` 指向单 Agent。因此“拆成 workflow”等价于新建 `data_pipeline` 工作流并把步骤显式节点化。

### 2.3 已下载的可用依赖（本地已就绪）

- 14 个 tool、11 个 BO、2 个 deeplink，位于 `src/tools`、`src/businessObjects`、`src/deeplinks`。
- 关键 BO 函数与参数（来自本地 `.bo` 文件）：
  - `ORA_SCM_INVENTORYM_INVENTORYACCESS/getall_inventoryAccessibleOrganizations`：`pOrganizationName,pOrganizationCode`
  - `ORA_SCM_INVENTORYM_VALIDATEINVENTORYITEMS/getall_itemsLOV`：`pItemNumber,pOrganizationCode`
  - `ORA_SCM_INVENTORYM_RESERVATIONDETA/getall_inventoryReservationDetails`：`pLimit,pOffset,pQuery`
  - `ORA_SCM_INVENTORYM_WORKORDERDEMAND/getall_WorkOrderDemandsInOtherOrgs`：`pOrgCode,pItemId`
  - `ORA_SCM_INVENTORYM_INVENTORYSTANDA/getall_invOrderReservationStatuses`：`pLimit,pOffset,pQuery,pFinder`
  - `ORA_SCM_INVENTORYM_RESERVATIONSDOC/getall_reservationsByDocumentLines`：`pLimit,pOffset,pDemandSourceTypeId,pDemandSourceHeaderId,pOrganizationCode`
  - `ORA_SCM_INVENTORYM_INVENTORYSUPPLY/getall_availableToReserveByDocumentTypes`：`pInventoryItemId,pOrganizationId,pOrderedUOM`
  - `ORA_SCM_INVENTORYM_SUPPLYDOCUMENTD/getall_supplyLineDetailsByTypes`：`pLimit,pOffset,pSupplySourceTypeId,pInventoryItemId,pOrganizationId,pOrderedUOM`
  - `ORA_SCM_INVENTORYM_RESERVATIONSMAI/create_inventoryReservations` / `update_inventoryReservations` / `delete_inventoryReservations`
- 深链工具：`ORA_INVENTORY_MANAGE_RESERVATIONS_TOOL`（参数 `pOrganizationId,pSupplySourceTypeId,pDemandSourceTypeId,pDemandSourceHeaderId`）、`ORA_DEMAND_DOCUMENTS_TOOL`（参数 `pDemandSourceTypeId,pOrganizationId`）。

## 3. 目标架构

### 3.1 总体结构

```
START → GET_USER_SESSION → CLASSIFY_REQUEST
      → CHECK_ORG →(true) VALIDATE_ORG
                  ↘(false)────────────────┐
      → CHECK_ITEM →(true) VALIDATE_ITEM
                   ↘(false)───────────────┤
                                          → ROUTE_ACTION → 各业务分支 → END
```

- `GET_USER_SESSION`：确定性 TOOL 节点，提供显示名/语言/时区。
- `CLASSIFY_REQUEST`：唯一的“自然语言入口”LLM 节点，负责把用户这一轮的话（结合历史）映射成结构化入参，不再让 LLM 直接调工具。
- 中间取数全部用 `BO_FUNCTION` 节点，参数由 CODE 节点或上游输出拼接，避免 LLM 自由发挥。
- 每个业务分支末尾放一个 LLM 节点，只做“把结构化结果渲染成用户可读表格/提示”，不产生新的业务事实。

### 3.2 多轮状态策略（关键决策）

不使用隐藏 ID 或跨轮变量保存选择结果，改为 **每轮用用户看得到的业务编号回查 ID**：

- 需求单选中后，下一轮用 `DemandSourceHeaderNumber + DemandSourceTypeId` 通过 `getall_invOrderReservationStatuses`（`pQuery`）回查 `DemandSourceHeaderId`。
- 供给源/供给行同理，用 `SupplySourceHeaderNumber/LineNumber` 回查。
- 组织/物料用 `OrganizationCode/ItemNumber` 通过 `getall_inventoryAccessibleOrganizations`、`getall_itemsLOV` 回查 `OrganizationId/ItemId`。

这样每一轮都是自包含的确定性查询，不依赖会话级变量，也不把 ID 暴露给用户。

## 4. 节点清单

> 节点 code 全部大写；BO_FUNCTION 节点创建时传 `metadataPatch.businessObjectCode` 与 `functionName`，由 CLI 自动补 `outputSpecification`。LLM 节点输出统一使用 `{"type":"object","properties":{"result":{...}}}` 形状，下游统一写 `$output.result.*`。

### 4.1 主链路

| Node code | Type | 关键配置 / 输入 |
| --- | --- | --- |
| `START` | START | 由 `do-create-workflow` 自动生成 |
| `GET_USER_SESSION` | TOOL | `metadata.toolCode=ORA_USER_SESSION_TOOL` |
| `CLASSIFY_REQUEST` | LLM | `metadata.chatHistoryEnabled=true`；`systemPrompt` 承载原 Agent 的 Rules/参数映射规则；`prompt` 注入 `$context.$system.$inputMessage`、用户名/语言/时区；`outputSpecification.result` 字段见 4.2 |
| `CHECK_ORG` | CONDITION | `condition={{!!$context.$nodes.CLASSIFY_REQUEST.$output.result.organizationCode}}`；`true→VALIDATE_ORG`，`false→CHECK_ITEM`，`convergenceTargetId=CHECK_ITEM` |
| `VALIDATE_ORG` | BO_FUNCTION | `INVENTORYACCESS/getall_inventoryAccessibleOrganizations`；`pOrganizationCode={{$context.$nodes.CLASSIFY_REQUEST.$output.result.organizationCode}}` |
| `CHECK_ITEM` | CONDITION | `condition={{!!$context.$nodes.CLASSIFY_REQUEST.$output.result.itemNumber}}`；`true→VALIDATE_ITEM`，`false→ROUTE_ACTION`，`convergenceTargetId=ROUTE_ACTION` |
| `VALIDATE_ITEM` | BO_FUNCTION | `VALIDATEINVENTORYITEMS/getall_itemsLOV`；`pItemNumber`、`pOrganizationCode` |
| `ROUTE_ACTION` | SWITCH | `caseExpression={{$context.$nodes.CLASSIFY_REQUEST.$output.result.action}}`；`convergenceTargetId=end`；`success→GENERAL_HELP` |

### 4.2 `CLASSIFY_REQUEST` 输出契约（`result`）

| 字段 | 说明 |
| --- | --- |
| `action` | 必填枚举：`ViewReservations` / `FetchDemandDocuments` / `FetchDemandDocumentLineDetails` / `FetchSupplyDocuments` / `FetchSupplyDocumentLineDetails` / `CreateOrderReservation` / `AutoReserve` / `UpdateReservation` / `DeleteReservation` / `GeneralHelp` |
| `language`,`territory`,`timezone` | 来自会话或用户本轮语言 |
| `organizationCode`,`organizationName` | 可选 |
| `itemNumber`,`itemName` | 可选 |
| `customerName` | 可选（LIKE 匹配） |
| `demandSourceTypeId` | `2/8/1/5` 之一，或空 |
| `demandSourceHeaderNumber`,`demandSourceHeaderId` | 单号（用户可见）或已解析 ID |
| `demandSourceLineId`,`demandSourceLineNumber` | 行选择 |
| `reservationStatus` | `Unreserved` / `Partially Reserved` / `Reserved` |
| `expectedStartDate`,`expectedEndDate` | `YYYY-MM-DD` |
| `reservationMode` | `single` / `auto` / `none` |
| `supplySourceTypeId`,`supplySourceHeaderNumber`,`supplySourceLineNumber` | 单笔预留时使用 |
| `reservationId` | 更新/删除时使用 |
| `reservationQuantity`,`reservationUOMCode` | 可选 |
| `deleteConfirmed` | boolean |

### 4.3 分支节点

**A. 查看预留（`ViewReservations`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `PREPARE_VIEW_QUERY` | CODE | 由 4.2 字段拼 `pQuery`（=、LIKE、日期条件；`getall_inventoryReservationDetails` 仅有 `pQuery`，无 `pFinder`），返回 `{pQuery}` |
| `VIEW_RESERVATIONS` | BO_FUNCTION | `RESERVATIONDETA/getall_inventoryReservationDetails`；`pLimit=25`、`pOffset=0`、`pQuery` |
| `FORMAT_RESERVATIONS` | LLM | 渲染“需求单类型/单号/行号/ReservationQty/DemandQty/ExpectedDate/Item/Organization Code/UOM”，不显示任何 ID 字段 |

**B. 需求单查询（`FetchDemandDocuments`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `PREPARE_DEMAND_QUERY` | CODE | 按原 Agent 规则构造 `pFinder="&finder=filterByItemExpectedDate;BindItemId=..,BindExpectedStartDate=..,BindExpectedEndDate=.."`；`pQuery` 用 `OrganizationCode='x' AND upper(CustomerName) LIKE upper('y%')` 形式（不含 ItemNumber/ExpectedDate；Work order 时把 `ReservationStatus` 改写为 `ReservationStatusMeaning`）；追加 `&orderBy=ExpectedDate:desc`；输出 `demandRoute`（`WORK_ORDER` / `ORDER`） |
| `DEMAND_TYPE_ROUTER` | SWITCH | `caseExpression={{$context.$nodes.PREPARE_DEMAND_QUERY.$output.result.demandRoute}}`；`WORK_ORDER→DEMAND_DOCS_WO`，`ORDER→DEMAND_DOCS_ORDER`，`success→FORMAT_DEMAND_DOCS`，`convergenceTargetId=FORMAT_DEMAND_DOCS` |
| `DEMAND_DOCS_WO` | BO_FUNCTION | `INVENTORYWORKORDERDEMANDS/getall_WorkOrderDemandsInOtherOrgs`；`pOrgCode`、`pItemId` |
| `DEMAND_DOCS_ORDER` | BO_FUNCTION | `INVENTORYSTANDA/getall_invOrderReservationStatuses`；`pLimit=10`、`pOffset=0`、`pQuery`、`pFinder` |
| `FORMAT_DEMAND_DOCS` | LLM | 输出 5 列（类型/单号/Expected Date/Total Lines/Reservation Status）与下一步建议 |

**C. 需求行查询（`FetchDemandDocumentLineDetails`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `RESOLVE_DEMAND_HEADER` | BO_FUNCTION | `INVENTORYSTANDA/getall_invOrderReservationStatuses`；`pLimit=1`、`pOffset=0`、`pQuery` 由 `DemandSourceHeaderNumber`（+类型）构造 |
| `DEMAND_LINES` | BO_FUNCTION | `RESERVATIONSDOC/getall_reservationsByDocumentLines`；`pLimit=10`、`pOffset=0`、`pDemandSourceTypeId`、`pDemandSourceHeaderId=$context.$nodes.RESOLVE_DEMAND_HEADER.$output...`、`pOrganizationCode` |
| `FORMAT_DEMAND_LINES` | LLM | 类型/单号/行号/Expected Date/Demand Qty/Reserved Qty/UOM |

**D. 供给源查询（`FetchSupplyDocuments`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `SUPPLY_SOURCES` | BO_FUNCTION | `INVENTORYSUPPLY/getall_availableToReserveByDocumentTypes`；`pOrganizationId`（来自 `VALIDATE_*` 结果）、`pInventoryItemId`、`pOrderedUOM` |
| `FORMAT_SUPPLY_SOURCES` | LLM | Supply Document Type / Available To Reserve / Expected Date |

**E. 供给行查询（`FetchSupplyDocumentLineDetails`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `SUPPLY_LINES` | BO_FUNCTION | `SUPPLYDOCUMENTD/getall_supplyLineDetailsByTypes`；`pLimit=10`、`pOffset=0`、`pSupplySourceTypeId`、`pInventoryItemId`、`pOrganizationId`、`pOrderedUOM` |
| `FORMAT_SUPPLY_LINES` | LLM | 供给类型/单号/Item/行号/Total ATR/Reserved Qty/Reservation Status/UOM/Expected Date |

**F. 创建预留（`CreateOrderReservation` / `AutoReserve`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `CREATE_MODE_CHECK` | CONDITION | `condition={{$context.$nodes.CLASSIFY_REQUEST.$output.result.reservationMode === "single"}}`；`true→CREATE_SINGLE`，`false→PREPARE_CREATE_QUERY`，`convergenceTargetId=end` |
| `CREATE_SINGLE` | BO_FUNCTION | `RESERVATIONSMAI/create_inventoryReservations`；`pOrganizationId`、`pInventoryItemId`、`pDemandSourceTypeId`、`pDemandSourceHeaderId`、`pDemandSourceLineId`、`pDemandSourceLineNumber`、`pSupplySourceTypeId`、`pSupplySourceHeaderId`、`pSupplySourceLineId`、`pReservationQuantity`、`pReservationUOMCode` |
| `CREATE_LINK_SINGLE` | TOOL | `ORA_INVENTORY_MANAGE_RESERVATIONS_TOOL`；4 个深链参数 |
| `FORMAT_CREATE_SINGLE` | LLM | 成功行 + 深链；失败时输出 Demand Documents 深链（`ORA_DEMAND_DOCUMENTS_TOOL` 作为并列终态节点） |
| `PREPARE_CREATE_QUERY` | CODE | 复用 B 的 `pQuery/pFinder` 规则，输出 `{pQuery,pFinder}` |
| `CREATE_DEMAND_DOCS` | BO_FUNCTION | `INVENTORYSTANDA/getall_invOrderReservationStatuses` |
| `CREATE_DEMAND_LINES` | BO_FUNCTION | `RESERVATIONSDOC/getall_reservationsByDocumentLines` |
| `SELECT_ELIGIBLE_LINES` | CODE | 过滤 `ReservationStatus != "Reserved"` 且 `ReleasedStatus in ["R","B"]` 且 `AvailableToReserveOnhand >= RequestedQuantity`；返回 `{lines:[...]}`；全为 0 时返回空数组 |
| `CREATE_EACH_LINE` | LOOP | `loopType=PARALLEL`；`collection={{$context.$nodes.SELECT_ELIGIBLE_LINES.$output.result.lines}}`；内嵌管道 `START_CREATE_EACH_LINE → CREATE_ONE → END_CREATE_EACH_LINE` |
| `CREATE_ONE`（循环体内） | BO_FUNCTION | `RESERVATIONSMAI/create_inventoryReservations`；参数取 `{{$context.$nodes.CREATE_EACH_LINE.$currentItem.*}}`，`pSupplySourceTypeId="13"` |
| `CREATE_LINK` | TOOL | `ORA_INVENTORY_MANAGE_RESERVATIONS_TOOL` |
| `FORMAT_CREATE_AUTO` | LLM | 合并结果表 + 成功深链；失败行给出 Demand Documents 深链提示 |

**G. 更新预留（`UpdateReservation`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `UPDATE_RESERVATION` | BO_FUNCTION | `RESERVATIONSMAI/update_inventoryReservations`；`pReservationId`、`pReservationQuantity`、`pReservationUOMCode` |
| `UPDATE_LINK` | TOOL | `ORA_INVENTORY_MANAGE_RESERVATIONS_TOOL` |
| `FORMAT_UPDATE` | LLM | 更新结果 + 深链 |

> 原 Agent 的“更换供给源需先比较可用量再删/拆/建”特殊逻辑，v1 不实现，写入已知限制（见第 7 节）。

**H. 删除预留（`DeleteReservation`）**

| Node | Type | 配置 |
| --- | --- | --- |
| `CHECK_DELETE_CONFIRM` | CONDITION | `condition={{$context.$nodes.CLASSIFY_REQUEST.$output.result.deleteConfirmed === true}}`；`true→RESOLVE_DELETE_ID`，`false→FORMAT_DELETE_CANCEL`，`convergenceTargetId=end` |
| `RESOLVE_DELETE_ID` | BO_FUNCTION | `RESERVATIONDETA/getall_inventoryReservationDetails`；`pLimit=1`、`pOffset=0`、`pQuery` 由 `demandSourceHeaderNumber`（订单号）构造，回查 `ReservationId` |
| `DELETE_RESERVATION` | BO_FUNCTION | `RESERVATIONSMAI/delete_inventoryReservations`；`pReservationId={{$context.$nodes.RESOLVE_DELETE_ID.$output...ReservationId}}` |
| `FORMAT_DELETE` | LLM | 删除成功/失败提示 |
| `FORMAT_DELETE_CANCEL` | LLM | 输出原 Agent 的二次确认话术，等待下一轮 `Yes/No` |

**I. 兜底**

| Node | Type | 配置 |
| --- | --- | --- |
| `GENERAL_HELP` | LLM | 输出第 1 步引导语 + 可搜索条件建议 |

### 4.4 路由表（`ROUTE_ACTION.outcomes`）

| case | 目标节点 |
| --- | --- |
| `ViewReservations` | `PREPARE_VIEW_QUERY` |
| `FetchDemandDocuments` | `PREPARE_DEMAND_QUERY` |
| `FetchDemandDocumentLineDetails` | `RESOLVE_DEMAND_HEADER` |
| `FetchSupplyDocuments` | `SUPPLY_SOURCES` |
| `FetchSupplyDocumentLineDetails` | `SUPPLY_LINES` |
| `CreateOrderReservation` | `CREATE_MODE_CHECK` |
| `AutoReserve` | `CREATE_MODE_CHECK` |
| `UpdateReservation` | `UPDATE_RESERVATION` |
| `DeleteReservation` | `CHECK_DELETE_CONFIRM` |
| `GeneralHelp` | `GENERAL_HELP` |
| `success`（默认） | `GENERAL_HELP` |

## 5. 实施步骤

所有命令均在项目根 `c:\EEE\code\08_work\yamaguchi` 执行，CLI 走 `.trae\\skills\\aistudio\\scripts\\aistudio.js`；含认证/凭证的调用使用非沙箱模式。复杂 JSON（CODE 源码、输出契约、长表达式）一律写入 `%TEMP%\\aistudio-patches\\*.json` 后用 `@file` 传入，避免 shell 引号破坏。

### 步骤 0：创建工作流文件

```powershell
node .trae\skills\aistudio\scripts\aistudio.js do-create-workflow `
  --name "Inventory Reservations AI Assistant (workflow agent) v1.0 _YY" `
  --workflow-code INVENTORY_RESERVATIONS_AI_ASSISTANT_WORKFLOW_AGENT_V1_YY `
  --family SCM --product INVENTORY_MANAGEMENT `
  --description "Workflow-based split of RESERVATIONSWORKER_V10_YY: deterministic BO/tool nodes with LLM intent extraction and response rendering."
```

创建后确认：`architecture` 为 `data_pipeline`、`dataPipeline.rootNode=start`、存在 `START`/`END`。

### 步骤 1：主链路节点与连线

按 4.1 依次 `do-create-node`，再一次性 `do-modify-node-edges`：

```json
[
 {"action":"add","from":"START","to":"GET_USER_SESSION"},
 {"action":"add","from":"GET_USER_SESSION","to":"CLASSIFY_REQUEST"},
 {"action":"add","from":"CLASSIFY_REQUEST","to":"CHECK_ORG"},
 {"action":"add","from":"CHECK_ORG","to":"VALIDATE_ORG","outcome":"true"},
 {"action":"add","from":"CHECK_ORG","to":"CHECK_ITEM","outcome":"false"},
 {"action":"add","from":"VALIDATE_ORG","to":"CHECK_ITEM"},
 {"action":"add","from":"CHECK_ITEM","to":"VALIDATE_ITEM","outcome":"true"},
 {"action":"add","from":"CHECK_ITEM","to":"ROUTE_ACTION","outcome":"false"},
 {"action":"add","from":"VALIDATE_ITEM","to":"ROUTE_ACTION"}
]
```

（边命令若以 `outcomes` 映射方式表达，则等价使用 `do-modify-node --metadata-patch` 或边的 `outcome` 字段；以实际 `do-modify-node-edges` 校验结果为准。）

### 步骤 2：查询分支

创建 4.3 A–E 的节点，并按下列边连接（每个分支末尾 `FORMAT_*` → `end`）：

- `ROUTE_ACTION→PREPARE_VIEW_QUERY→VIEW_RESERVATIONS→FORMAT_RESERVATIONS→end`
- `ROUTE_ACTION→PREPARE_DEMAND_QUERY→DEMAND_TYPE_ROUTER`；`DEMAND_DOCS_WO→FORMAT_DEMAND_DOCS`、`DEMAND_DOCS_ORDER→FORMAT_DEMAND_DOCS`、`FORMAT_DEMAND_DOCS→end`
- `ROUTE_ACTION→RESOLVE_DEMAND_HEADER→DEMAND_LINES→FORMAT_DEMAND_LINES→end`
- `ROUTE_ACTION→SUPPLY_SOURCES→FORMAT_SUPPLY_SOURCES→end`
- `ROUTE_ACTION→SUPPLY_LINES→FORMAT_SUPPLY_LINES→end`

同时设置 `ROUTE_ACTION.outcomes` 与 `DEMAND_TYPE_ROUTER.outcomes`、两个 SWITCH 的 `convergenceTargetId`。

### 步骤 3：创建分支（含 LOOP）

创建 4.3 F 的节点；`CREATE_EACH_LINE` 需要按 `for-loop.md` 手工补齐内嵌 `metadata.dataPipeline`（`start_create_each_line` / `create_one` / `end_create_each_line`）与 `collection` 输入，再连接：

- `ROUTE_ACTION→CREATE_MODE_CHECK`
- `CREATE_MODE_CHECK→CREATE_SINGLE`（true）、`CREATE_MODE_CHECK→PREPARE_CREATE_QUERY`（false）
- `CREATE_SINGLE→CREATE_LINK_SINGLE→FORMAT_CREATE_SINGLE→end`
- `PREPARE_CREATE_QUERY→CREATE_DEMAND_DOCS→CREATE_DEMAND_LINES→SELECT_ELIGIBLE_LINES→CREATE_EACH_LINE→CREATE_LINK→FORMAT_CREATE_AUTO→end`

### 步骤 4：更新 / 删除 / 兜底

- `ROUTE_ACTION→UPDATE_RESERVATION→UPDATE_LINK→FORMAT_UPDATE→end`
- `ROUTE_ACTION→CHECK_DELETE_CONFIRM`；true→`RESOLVE_DELETE_ID→DELETE_RESERVATION→FORMAT_DELETE→end`，false→`FORMAT_DELETE_CANCEL→end`
- `ROUTE_ACTION→GENERAL_HELP→end`

### 步骤 5：校正下游表达式

每个 `BO_FUNCTION` / `TOOL` 节点创建后读取其 `outputSpecification`，把 `RESOLVE_DEMAND_HEADER`、`VALIDATE_*`、`CREATE_LINK*` 等引用改成真实字段路径（数组首项用 `?.` 安全访问）。重点核对：

- `GET_USER_SESSION.$output.result` 的显示名/语言/时区字段名
- `getall_invOrderReservationStatuses` 返回的 `documents[]` 与 header id 字段名
- `create_inventoryReservations` 返回的 `ReservationId` 路径
- 深链 TOOL 返回 URL 的字段名

### 步骤 6：校验

```powershell
node .trae\skills\aistudio\scripts\aistudio.js do-prettify-workflow --file src/workflows/inventory_reservations_ai_assistant_workflow_agent_v1_yy.wf
node .trae\skills\aistudio\scripts\aistudio.js validate-workflow --file src/workflows/inventory_reservations_ai_assistant_workflow_agent_v1_yy.wf
```

若校验报表达式/字段错误，回到步骤 5 修正后重跑。

### 步骤 7：测试同步

工作流创建成功后按 skill 要求执行：

```powershell
node .trae\skills\aistudio\scripts\aistudio.js get-workflow-test-sync-plan --file src/workflows/inventory_reservations_ai_assistant_workflow_agent_v1_yy.wf
```

按计划补测试并执行；最后用 `get-workflow-test-final-summary --file ...` 输出验证结果。**不发布、不设置 PUBLISHED 状态。**

## 6. 假设与决策

1. **拆分形态**：确定性节点 + LLM（用户已确认）。
2. **落地方式**：新建工作流文件，原 `.agent` 与原单 agent `.wf` 不动（用户已确认）。
3. **不引入会话级变量**：所有跨轮选择通过用户可见业务编号回查 ID。
4. **不显示 ID**：所有 `FORMAT_*` 的 prompt 明确禁止输出任何 `*Id` 字段。
5. **语言**：沿用原 Agent 规则，按会话 `Language` 输出；`CLASSIFY_REQUEST` 与所有 `FORMAT_*` 共享该规则，不再硬编码日语。
6. **分页**：v1 固定 `pOffset=0`，查询类 `pLimit=10`（预留明细 `25`），不实现翻页。
7. **校验失败文案**：沿用原 Agent 的 `Invalid organization...` / `Invalid item...` 文案，由对应 CONDITION 的 false 分支或 `GENERAL_HELP` 输出。
8. **创建失败优先级**：`AvailableToReserveOnhand` 不足时使用 Demand Documents 深链提示；这部分在 `FORMAT_CREATE_*` 中按条件拼接。

## 7. 已知限制 / 后续增强

- “更换供给源”的删/拆/建特殊逻辑不在 v1（原 Agent 的 step 7 附注），后续可加 `GET_NEW_SUPPLY_ATR → COMPARE_ATR → DELETE_OLD / UPDATE_REDUCED → CREATE_NEW` 子图。
- 翻页（“Refine/paging”）v1 不实现。
- `getall_WorkOrderDemandsInOtherOrgs` 只接受 `pOrgCode/pItemId`，因此 Work order 查询无法复用 `pFinder` 日期过滤；与依赖该过滤的场景存在行为差异。
- 工作流的 `architecture` 由 CLI 生成为 `data_pipeline`；若平台要求 `multi_agent` 标识，需要在 UI 侧确认，CLI 不提供该字段修改命令。

## 8. 验证清单

- [ ] 新 `.wf` 仅新增，未修改/删除原 workflow 与 agent 文件
- [ ] `validate-workflow` 通过，无悬空节点、无未声明输出字段引用
- [ ] 每个 SWITCH 的 case 均有对应 `outcomes` 与 `success` 默认分支
- [ ] 每个 CONDITION 都有 `true`/`false`/`convergenceTargetId`
- [ ] LOOP 内嵌管道具备 `collection`、`loopType`、`rootNode`、内部 START/END
- [ ] 所有 FORMAT prompt 明确禁止输出 ID 字段
- [ ] 测试同步流程完成，并在最终回复中给出 `Validation and Insights`
