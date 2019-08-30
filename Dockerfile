FROM node:12.9.1

RUN npm install -g cloudflare-cli
RUN apt-get update
RUN apt-get install jq
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
RUN kubectl version --client

ADD k8s-tools.sh /k8s-tools.sh
RUN chmod +x /k8s-tools.sh

