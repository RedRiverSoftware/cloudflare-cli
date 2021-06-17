#!/bin/bash

echo cloudflare-cli: k8s-tools v0.0.10

bad=0
if [ -z "$action" ]; then echo "variable 'action' is not set"; bad=1; fi
if [ -z "$subdomain" ]; then echo "variable 'subdomain' is not set"; bad=1; fi
if [ -z "$CF_API_KEY" ]; then echo "variable 'CF_API_KEY' is not set"; bad=1; fi
if [ -z "$CF_API_EMAIL" ]; then echo "variable 'CF_API_EMAIL' is not set"; bad=1; fi
if [ -z "$CF_API_DOMAIN" ]; then echo "variable 'CF_API_DOMAIN' is not set"; bad=1; fi
if [ $action = "create" ]; then
	if [ -z "$service" ]; then
		if [ -z "$ingress" ]; then echo "both variables 'service' and 'ingress' are not set"; bad=1;fi
	fi
	if [ -z "$deployment" ]; then echo "variable 'deployment' is not set"; bad=1; fi
	if [ -z "$namespace" ]; then echo "variable 'namespace' is not set"; bad=1; fi
fi
if [ $bad -eq 1 ]
then
	echo "please set variables: action, subdomain, CF_API_KEY, CF_API_EMAIL, CF_API_DOMAIN"
	echo "if action is create, please specify these variables too: namespace, deployment, and either service or ingress"
	echo "valid actions: create, delete"
	exit 1
fi

record_type=${CF_DNS_TYPE:="A"}
bad=1
if [ $action = "create" ]; then
	bad=0

	echo waiting for deployment to rollout...
	kubectl --namespace=$namespace rollout status deployment/$deployment

	if [ -n "$ingress" ]
	then
		echo getting ingress info...
		resource=$(kubectl --namespace=$namespace get ingress $ingress --output=json)
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo failed
			exit 1
		fi
		if [ -z "$resource" ]; then echo "no ingress data returned"; exit 1; fi
		echo got ingress info
	else
		echo getting service info...
		resource=$(kubectl --namespace=$namespace get service $service --output=json)
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo failed
			exit 1
		fi
		if [ -z "$resource" ]; then echo "no service data returned"; exit 1; fi
		echo got service info
	fi
	echo getting external IP...
	ip=$(echo "$resource" | jq -r '.status.loadBalancer.ingress | .[] | .ip')
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo failed
		exit 1
	fi
	if [ -z "$ip" ]; then echo "ip not found"; exit 1; fi
	echo public IP: $ip

	echo deleting any existing record...
	cfcli -e $CF_API_EMAIL -k $CF_API_KEY -d $CF_API_DOMAIN -a -t $record_type rm $subdomain

    echo adding...
    cfcli -e $CF_API_EMAIL -k $CF_API_KEY -d $CF_API_DOMAIN -a -t $record_type add $subdomain $ip
    retVal=$?
fi
if [ $action = "delete" ]; then
	bad=0
    echo deleting...
	cfcli -e $CF_API_EMAIL -k $CF_API_KEY -d $CF_API_DOMAIN -a -t $record_type rm $subdomain
    retVal=$?
fi
if [ $bad -eq 1 ]; then echo "unknown action - use create or delete"; exit 1; fi

if [ $retVal -ne 0 ]; then
	echo failed
	exit 1
fi
echo success!
