# Admin API

## User credentials (password grant)

For scripting and one-off automation. Token expires after 10 minutes.

```bash
TOKEN=$(curl -s -X POST https://sdwa5.org/api/oauth/token \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"password","client_id":"administration","username":"admin","password":"<admin-password>"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s https://sdwa5.org/api/product \
  -H "Authorization: Bearer $TOKEN"
```

## Integration (client credentials grant)

Integration "Claude MCP" (admin=true) registered in `/home/stefanr/.claude.json` (project scope) as `shopware-admin-mcp`
MCP server.

```bash
TOKEN=$(curl -s -X POST https://sdwa5.org/api/oauth/token \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"client_credentials","client_id":"<accessKey>","client_secret":"<secretAccessKey>"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

MCP tools: `product_list/get/create/update`, `category_list/create/update/delete`, `order_list/detail/update`,
`sales_channel_list/update`, `theme_config_get/change`, `upload_media_by_url`, `dal_aggregate`, `fetch_entity_list`,
`fetch_single_entity_schema`

## Key API patterns

```bash
# Search / filter
POST /api/search/product   body: {"filter":[{"type":"equals","field":"active","value":true}]}

# PATCH requires versionId on cms_slot
PATCH /api/cms-slot/<id>   body: {"versionId":"0fa91ce3e96a4bc2be4bd9ce752c3425", ...}

# CMS slot with bilingual content
PATCH /api/cms-slot/<id>   body: {"versionId":"...", "translations": {"<langId>": {"config": {"content": {"value": "<html>", "source": "static"}}}}}

# Snippet override (per locale)
POST /api/snippet   body: {"setId":"<snippetSetId>","translationKey":"<key>","value":"<val>","author":"user"}
# Known snippet keys: detail.reachable = "No longer available" label on out-of-stock products (isCloseout=true, stock=0)

# System config
POST /api/_action/system-config   body: {"null":{"core.basicInformation.shopName":"SdWa5"}}

# Clear HTTP cache
DELETE /api/_action/cache
```
