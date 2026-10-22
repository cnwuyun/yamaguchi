{
  "toolId": "100002354806110",
  "$context": {
    "etag": "1"
  },
  "createdBy": "SEED_DATA_FROM_APPLICATION",
  "toolCreatedDate": "2026-01-09",
  "toolCode": "ORA_INVENTORY_WORK_ORDER_DEMANDS_TOOL",
  "name": "Inventory Work Order Demands Tool",
  "description": "This tool fetches work order demands across inventory organizations using the organization code and item identifier.",
  "family": "SCM",
  "product": "INVENTORY_MANAGEMENT",
  "type": "BUSINESS_OBJECT",
  "status": "DRAFT",
  "version": 1,
  "userInputRequiredFlag": false,
  "userInputMessage": "",
  "subType": "",
  "namespace": "SCM.INVENTORY_MANAGEMENT",
  "specification": {
    "customFlag": false,
    "jsonSchemaName": "Tool.spec",
    "jsonSchemaVersion": "1",
    "businessObjectMetadata": {
      "functions": [
        "getall_WorkOrderDemandsInOtherOrgs"
      ]
    },
    "externalRestMetadata": {
      "endpoints": [],
      "instanceURL": "",
      "extensionId": "",
      "serviceConnectionId": "",
      "authInfo": {}
    },
    "mcpConfig": {
      "credentialId": "",
      "credentialType": "none",
      "instanceURL": "",
      "tools": [],
      "type": "sse"
    },
    "kmConnectorConfig": {
      "connectorReferenceKey": "",
      "externalDocId": "",
      "externalDocVersionId": "",
      "type": "",
      "filters": [],
      "tools": []
    },
    "ragDocumentMetadata": {
      "authorization": {},
      "content": {},
      "contentArray": []
    },
    "sourceObjectCode": "",
    "uiInput": {
      "responseSpec": "",
      "uiPatternSpec": "",
      "uiPatternType": "",
      "userInputType": ""
    }
  },
  "restTool": [
    {
      "restToolId": "100002355015243",
      "toolCode": "ORA_INVENTORY_WORK_ORDER_DEMANDS_TOOL",
      "toolId": "100002354806110",
      "payloadTemplate": "",
      "specification": "",
      "seededFlag": true,
      "supportedObject": {
        "supportedObjectId": "100002354783114"
      },
      "$context": {
        "etag": "1"
      }
    }
  ],
  "deepLinkTool": [],
  "retrievalDocuments": [],
  "messageDeliveryOptions": []
}
