{
  "toolId": "100002354806111",
  "$context": {
    "etag": "1"
  },
  "createdBy": "SEED_DATA_FROM_APPLICATION",
  "toolCreatedDate": "2026-01-09",
  "toolCode": "ORA_VALIDATE_INVENTORY_ITEMS_TOOL",
  "name": "Validate Inventory Items Tool",
  "description": "Tool to retrieve item, product, material details.",
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
        "getall_itemsLOV"
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
      "restToolId": "100002355015244",
      "toolCode": "ORA_VALIDATE_INVENTORY_ITEMS_TOOL",
      "toolId": "100002354806111",
      "payloadTemplate": "",
      "specification": "",
      "seededFlag": true,
      "supportedObject": {
        "supportedObjectId": "100002354783115"
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
