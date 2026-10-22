{
  "toolId": "100002240185209",
  "$context": {
    "etag": "1"
  },
  "createdBy": "SEED_DATA_FROM_APPLICATION",
  "toolCreatedDate": "2025-10-09",
  "toolCode": "ORA_DEMAND_DOCUMENTS_TOOL",
  "name": "Demand Documents Tool",
  "description": "A tool that gets the URL to allow the user to navigate to Search Document Demand Redwood page with specified identifiers.",
  "family": "SCM",
  "product": "INVENTORY_MANAGEMENT",
  "type": "DEEP_LINK",
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
      "functions": []
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
  "restTool": [],
  "deepLinkTool": [
    {
      "deepLinkToolId": "100002240362810",
      "toolCode": "ORA_DEMAND_DOCUMENTS_TOOL",
      "toolId": "100002240185209",
      "seededFlag": true,
      "deepLink": {
        "deepLinkId": "100002240138750",
        "name": "Demand Documents DL",
        "family": "SCM",
        "product": "INVENTORY_MANAGEMENT",
        "description": "URL to navigate to Search Document Demand Redwood page.",
        "message": "Click {deepLink} for details.",
        "seededFlag": true
      },
      "$context": {
        "etag": "1"
      }
    }
  ],
  "retrievalDocuments": [],
  "messageDeliveryOptions": []
}
