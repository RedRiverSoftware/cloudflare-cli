# cloudflare-cli

This tool is used as aprt of our [helm charts](https://github.com/RedRiverSoftware/k8s/tree/master/helm3-charts) to manage Cloudflare DNS records automatically post deployment.

## Update the Docker image

Authenticate to the Azure Container Registry:

```bash
az acr login -n RedRiver
```

Build and push the image to the Azure Container Registry:

```bash
docker build . --tag redriver.azurecr.io/cloudflare-cli:VERSION --push
```
