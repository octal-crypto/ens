#!/bin/bash -e

if [[ $# == 0 ]]
then
    echo "Usage: $0 domain1 domain2 domainN"
    echo "Searches a list of ENS domains."
    exit 1
fi

names=($(sort -u <<< $(printf "%s\n" ${@,,})))
echo "Looking up ${#names[@]} ENS domains."

url="https://api.thegraph.com/subgraphs/name/ensdomains/ens"
query="(\$names:[String!]){registrations(first:1000,\
        where:{labelName_in:\$names},orderBy:labelName,orderDirection:asc)\
        {labelName expiryDate registrant{id}}}"

results="Name\tOwner\tExpiry\tError\n"
red="\033[0;31m"
green="\033[0;32m"

# Query in 1,000 record batches (the most the subgraph will return)
for ((n=0; n<${#names[@]}; n+=1000));
do
    batch=(${names[@]:$n:1000})
    list=$(printf '"%s",' ${batch[@]})
    body="{\"query\":\"query $query\",\"variables\":{\"names\":[${list::-1}]}}"
    resp=$(curl -sSw '\n%{http_code}' -d "$body" "$url")
    code=$(tail -n1 <<< "$resp")
    body=$(head -n1 <<< "$resp")

    if [[ "$code" != "200" || $(jq .errors <<< "$body") != "null" ]]
    then
        echo "$resp"
        exit 1
    fi

    jq=".data.registrations[]|[.labelName,.registrant.id,.expiryDate]|@tsv"
    readarray registrations <<< $(jq -rS "$jq" <<< "$body")

    IFS=$'\t' read reg owner expiry <<< ${registrations[0]}
    for name in "${batch[@]}"
    do
        if [[ "${#name}" -lt 3 ]]
        then
            results+="${red}${name}\t\t\tDomains must be >= 3 characters\n"
        elif [[ "$reg" == "$name" ]]
        then
            expiry=$(date -d "@$expiry" "+%B %e %Y")
            results+="${red}${name}\t${owner}\t${expiry}\n"
            r=$((r+1))
            IFS=$'\t' read reg owner expiry <<< ${registrations[$r]}
        else
            results+="${green}${name}\tAvailable\n"
        fi
    done
done

echo -e "$results" | column -tns $'\t'
