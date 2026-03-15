#!/bin/bash

echo cloudflare-cli: k8s-tools v0.0.23

bad=0
if [ -z "$action" ]; then echo "variable 'action' is not set"; bad=1; fi
if [ -z "$subdomain" ]; then echo "variable 'subdomain' is not set"; bad=1; fi
if [ -z "$use_proxy" ]; then echo "variable 'use_proxy' is not set"; bad=1; fi
if [ -z "$CF_API_KEY" ]; then echo "variable 'CF_API_KEY' is not set"; bad=1; fi
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
	echo "please set variables: action, subdomain, CF_API_KEY, CF_API_DOMAIN"
	echo "if action is create, please specify these variables too: namespace, deployment, and either service or ingress"
	echo "valid actions: create, delete"
	exit 1
fi

record_type=${CF_DNS_TYPE:="A"}
bad=1

zone_id=$(curl https://api.cloudflare.com/client/v4/zones?name=$CF_API_DOMAIN \
-H "Authorization: Bearer $CF_API_KEY" | jq -r ".result[] | select(.name | contains(\"$CF_API_DOMAIN\")) | .id")
if [ -z "$zone_id" ]; then echo "zone not found"; exit 1; fi

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
	if [ $record_type = "A" ]
	then
		echo getting external IP...
		dns_record_value=$(echo "$resource" | jq -r '.status.loadBalancer.ingress | .[] | .ip')
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo failed
			exit 1
		fi
		if [ -z "$dns_record_value" ]; then echo "ip not found"; exit 1; fi
		echo public IP: $dns_record_value
	else
		echo getting external hostname...
		dns_record_value=$(echo "$resource" | jq -r '.status.loadBalancer.ingress | .[] | .hostname')
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo failed
			exit 1
		fi
		if [ -z "$dns_record_value" ]; then echo "hostname not found"; exit 1; fi
		echo public Host Name: $dns_record_value
	fi

	echo looking up existing record to delete...
	cloudflare_record_id=$(curl https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?search=$subdomain \
    -H "Authorization: Bearer $CF_API_KEY" | jq -r ".result[] | select(.name | contains(\"$subdomain\")) | .id")

	if [ -z "$cloudflare_record_id" ]
	then
		echo creating for first time...
		curl https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $CF_API_KEY" \
		-d '{
		"content": "'$dns_record_value'",
		"name": "'$subdomain'",
		"proxied": '$use_proxy',
		"type": "'$record_type'"
		}'
		retVal=$?
	else
		echo updating...
		curl https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$cloudflare_record_id \
		-X PATCH \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $CF_API_KEY" \
		-d '{
		"content": "'$dns_record_value'",
		"name": "'$subdomain'",
		"proxied": '$use_proxy',
		"type": "'$record_type'"
		}'
		retVal=$?
	fi
fi
if [ $action = "delete" ]; then
	bad=0
	echo deleting...
	echo looking up existing record to delete...
	cloudflare_record_id=$(curl https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?search=$subdomain \
    -H "Authorization: Bearer $CF_API_KEY" | jq -r ".result[] | select(.name | contains(\"$subdomain\")) | .id")

	echo deleting...
	curl https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$cloudflare_record_id \
    -X DELETE \
    -H "Authorization: Bearer $CF_API_KEY"
    retVal=$?
fi
if [ $bad -eq 1 ]; then echo "unknown action - use create or delete"; exit 1; fi

if [ $retVal -ne 0 ]; then
	echo failed
	exit 1
fi
echo success!
