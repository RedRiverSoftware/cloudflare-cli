FROM node:16-alpine

RUN npm install -g cloudflare-cli
RUN apk update && apk add --no-cache jq curl bash
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
RUN kubectl version --client

ADD k8s-tools.sh /k8s-tools.sh
RUN chmod +x /k8s-tools.sh
