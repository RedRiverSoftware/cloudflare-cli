## Build with docker buildx:

docker buildx build --platform linux/amd64,linux/arm64 . -f ./Dockerfile --tag docker.io/redriversoftware/cloudflare-cli:VERSION --push