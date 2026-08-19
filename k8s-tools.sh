#!/bin/bash

echo cloudflare-cli: k8s-tools v0.0.24

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

# An API token authenticates as a bearer; a Global API Key needs the account email alongside it.
# Both are accepted, so a chart still supplying CF_API_EMAIL keeps working on this version.
if [ -n "$CF_API_EMAIL" ]; then
	auth=(-H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY")
else
	auth=(-H "Authorization: Bearer $CF_API_KEY")
fi

# The record this invocation owns, as Cloudflare names it. Every lookup below matches it exactly.
case "$subdomain" in
	*".$CF_API_DOMAIN") fqdn="$subdomain" ;;
	*) fqdn="$subdomain.$CF_API_DOMAIN" ;;
esac

zone_id=$(curl -s -G https://api.cloudflare.com/client/v4/zones \
--data-urlencode "name=$CF_API_DOMAIN" \
"${auth[@]}" | jq -r --arg zone "$CF_API_DOMAIN" '.result[] | select(.name == $zone) | .id')
if [ -z "$zone_id" ]; then echo "zone not found"; exit 1; fi

# Sets $cloudflare_record_id to the id of the record named $fqdn, or to the empty string.
#
# Matching is exact in both the query and the filter. The API's `search` parameter is a substring
# filter, so looking up `pepper` also returns `pepper-mcp`, and a deploy of one service would then
# rewrite or delete another service's record.
#
# Assigns to a global rather than printing: called through $(...) it would run in a subshell, where
# the exit below would end only that subshell and hand the caller an empty id - which reads as "no
# record exists", so a duplicate would quietly add another instead of stopping.
lookup_record_id() {
	cloudflare_record_id=$(curl -s -G "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
	--data-urlencode "name=$fqdn" \
	--data-urlencode "type=$record_type" \
	"${auth[@]}" | jq -r --arg fqdn "$fqdn" '.result[] | select(.name == $fqdn) | .id')

	if [ "$(printf '%s' "$cloudflare_record_id" | grep -c .)" -gt 1 ]; then
		echo "found more than one $record_type record named $fqdn - refusing to guess" >&2
		exit 1
	fi
}

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

	echo "looking up existing $record_type record for $fqdn..."
	lookup_record_id

	if [ -z "$cloudflare_record_id" ]
	then
		echo creating for first time...
		curl -s https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records \
		-H 'Content-Type: application/json' \
		"${auth[@]}" \
		-d '{
		"content": "'$dns_record_value'",
		"name": "'$fqdn'",
		"proxied": '$use_proxy',
		"type": "'$record_type'"
		}'
		retVal=$?
	else
		echo updating...
		curl -s "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$cloudflare_record_id" \
		-X PATCH \
		-H 'Content-Type: application/json' \
		"${auth[@]}" \
		-d '{
		"content": "'$dns_record_value'",
		"name": "'$fqdn'",
		"proxied": '$use_proxy',
		"type": "'$record_type'"
		}'
		retVal=$?
	fi
fi
if [ $action = "delete" ]; then
	bad=0
	echo "looking up existing $record_type record for $fqdn..."
	lookup_record_id

	if [ -z "$cloudflare_record_id" ]
	then
		echo "no $record_type record named $fqdn - nothing to delete"
		retVal=0
	else
		echo deleting...
		curl -s "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$cloudflare_record_id" \
		-X DELETE \
		"${auth[@]}"
		retVal=$?
	fi
fi
if [ $bad -eq 1 ]; then echo "unknown action - use create or delete"; exit 1; fi

if [ $retVal -ne 0 ]; then
	echo failed
	exit 1
fi
echo success!
