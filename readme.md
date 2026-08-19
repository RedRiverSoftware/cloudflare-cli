# cloudflare-cli

This tool is used as aprt of our [helm charts](https://github.com/RedRiverSoftware/k8s/tree/master/helm3-charts) to manage Cloudflare DNS records automatically post deployment.

## Authentication

Set `CF_API_KEY` to a Cloudflare API token and leave `CF_API_EMAIL` unset, or set `CF_API_KEY` to a
Global API Key and `CF_API_EMAIL` to the account address. The presence of `CF_API_EMAIL` selects
between the two, so a chart still passing it keeps working.

## Record matching

A record is matched by its exact name, `$subdomain.$CF_API_DOMAIN`. Cloudflare's `search` parameter
is a substring filter, so matching on the subdomain alone lets one service act on another's record
whenever one name is a prefix of another — `pepper` against `pepper-mcp`, for instance. If a zone
somehow holds more than one matching record, the script stops rather than guessing.

## Update the Docker image

Authenticate to the Azure Container Registry:

```bash
az acr login -n RedRiver
```

Build and push the image to the Azure Container Registry:

```bash
docker build . --tag redriver.azurecr.io/cloudflare-cli:VERSION --push
```
