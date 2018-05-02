#!/bin/bash

## Prerequisites:
#
# 1. Add custom field for nsp-vuln-id in JIRA:
#  - Settings --> Issues --> Custom Fields --> Add Custom Field -->
#       Text Field Single Line
#       'nsp-vuln-id'
#       Select relevant project screens
#
# 2. Add custom field for nsp-path in JIRA:
#  - Settings --> Issues --> Custom Fields --> Add Custom Field -->
#       Text Field Single Line
#       'nsp-path'
#       Select relevant project screens
#
# 3. Create .jirac file in local directorty with four lines
# export JIRA_USER=<USER>
# export JIRA_PASSWORD=<PWD>
# export BASE_JIRA_URL=<URL>
# export JIRA_PROJECT_NAME=<PROJECT>

## Debug: DEBUG=1 to activate, DEBUG= to deactivate
DEBUG=
## Add comment: ADD_COMMENT=1 to add comment if open issue with same vuln already exists. ADD_COMMENT= to skip
ADD_COMMENT=

JIRA_NSP_CUSTOM_FIELD_VULN_NAME=nsp-vuln-id
JIRA_NSP_CUSTOM_FIELD_PATH_NAME=nsp-path


## .jirarc format:
# export JIRA_USER=<USER>
# export JIRA_PASSWORD=<PWD>
if [ -r .jirarc ]
then
  source .jirarc
else
  echo ".jirarc file not found"
  exit 1
fi

[ $JIRA_USER ] || (echo JIRA_USER not specified && exit 1)
[ $JIRA_PASSWORD ] || (echo JIRA_PASSWORD not specified && exit 1)
[ $BASE_JIRA_URL ] || (echo BASE_JIRA_URL not specified && exit 1)
[ $JIRA_PROJECT_NAME ] || (echo BASE_JIRA_URL not specified && exit 1)

function usage()
{
  echo "Usage: $0 <nsp-test.json>"
  echo "nsp-test.json should be the output of running 'nsp check --reporter json > nsp-test.json'"
}

function uc_first()
{
  local UC_FIRST=`echo -n ${1:0:1} | tr  '[a-z]' '[A-Z]'`${1:1}
  echo $UC_FIRST
}

function urlencode()
{
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

function jira_curl()
{
  local API=$1
  local COMMAND=${2:-"GET"}
  local DATA_FILE=$3
  if [[ $COMMAND == "POST" ]] ; then
    curl -s -S -u $JIRA_USER:$JIRA_PASSWORD -X $COMMAND --data @$DATA_FILE -H "Content-Type: application/json" $BASE_JIRA_URL/rest/api/2/$API
  else
    curl -s -S -u $JIRA_USER:$JIRA_PASSWORD -X $COMMAND -H "Content-Type: application/json" $BASE_JIRA_URL/rest/api/2/$API
  fi
}

function jira_get_project_id()
{
  local PROJECT_NAME=$1
  local PROJECT_ID=`jira_curl issue/createmeta | jq ".projects[] | select(.name==\"$PROJECT_NAME\") | .id" | tr -d '\"'`
  local re='^[0-9]+$'
  if ! [[ $PROJECT_ID =~ $re  ]] ; then
   echo "Error: could not find project with name $PROJECT_NAME" >&2
   exit 1
  fi
  echo $PROJECT_ID;
}

function jira_get_custom_field_id()
{
  local CUSTOM_FIELD_NAME=$1
  local CUSTOM_FIELD_ID=`jira_curl field | jq ".[] | select(.name==\"$CUSTOM_FIELD_NAME\") | .id" | tr -d '\"'`
  local re='^customfield_[0-9]+$'
  if ! [[ $CUSTOM_FIELD_ID =~ $re  ]] ; then
   echo "Error: could not find field with name $CUSTOM_FIELD_NAME" >&2
   exit 1
  fi
  echo $CUSTOM_FIELD_ID;
}

function jira_create_issue()
{
  local PROJECT_ID=$1
  local SUMMARY=$2
  local NSP_VULN_ID=$3
  local NSP_PATH=$4
  local SEVERITY=`uc_first $5`

  local NSP_VULN_ID_ENC=`urlencode "$NSP_VULN_ID"`
  local NSP_PATH_ENC=`urlencode "$NSP_PATH"`

  local PAYLOAD_FILE=`mktemp`

  local ISSUE_KEY=`jira_curl "search?jql=project=$PROJECT_ID+AND+status!=Done+AND+$JIRA_NSP_CUSTOM_FIELD_VULN_NAME~$NSP_VULN_ID_ENC+AND+$JIRA_NSP_CUSTOM_FIELD_PATH_NAME~\"$NSP_PATH_ENC\"&maxResults=1&fields=id,key" | jq '.issues[0].key' | tr -d '"'`

  local re='^[A-Za-z]{3}-[0-9]+$'
  if [[ $ISSUE_KEY =~ $re ]] ; then
    ## Issue with same vuln and path exists
    if [[ $ADD_COMMENT == 1 ]] ; then
      [ $DEBUG ] && echo "Found exising issue with nsp-vuln-id=$NSP_VULN_ID (id=$ISSUE_KEY) [$NSP_PATH] --> Adding comment"
      cat > $PAYLOAD_FILE <<EOM
{
    "body": "Vulnerability not resolved yet"
}
EOM
      jira_curl issue/$ISSUE_KEY/comment POST $PAYLOAD_FILE | grep -v "self"
    else
      [ $DEBUG ] && echo "Found exising issue with nsp-vuln-id=$NSP_VULN_ID (id=$ISSUE_KEY) [$NSP_PATH] --> Skipping"
    fi
  else
    ## New issue
    [ $DEBUG ] && echo "Creating new issue for nsp-vuln-id=$NSP_VULN_ID: $SUMMARY"

      cat > $PAYLOAD_FILE <<EOM
{
  "fields": {
    "project": {
      "id": "$PROJECT_ID"
    },
    "summary": "$SUMMARY",
    "priority": {
      "name": "$SEVERITY"
    },
    "issuetype": {
      "name": "Bug"
    },
    "description": "For more information please refer to https://nodesecurity.io/advisories/$NSP_VULN_ID",
    "$JIRA_NSP_CUSTOM_FIELD_VULN_ID": "$NSP_VULN_ID",
    "$JIRA_NSP_CUSTOM_FIELD_PATH_ID": "$NSP_PATH"
  }
}
EOM
    jira_curl issue POST $PAYLOAD_FILE
    echo
  fi

}

####################
# START OF PROGRAM
####################
if ! [ $# -eq 1 ]; then
  usage
  exit 1
fi

JSON_FILE=$1
if ! [ -r $JSON_FILE ]; then
  echo "Could not open $JSON_FILE for reading"
  exit 1
fi

N_VULNS=`cat $JSON_FILE | jq '.vulnerabilities | length'`

re='^[0-9]+$'
if ! [[ $N_VULNS =~ $re ]]; then
  echo $JSON_FILE does not [$N_VULNS] seem to be an output of 'nsp check --reporter json'
  exit 1
fi

if [ $N_VULNS -eq 0 ]; then
  echo "Good for you! No vulns found."
  exit 0
fi

[ $DEBUG ] && echo Found $N_VULNS vulns

[ $DEBUG ] && echo Connecting with user $JIRA_USER
[ $DEBUG ] && echo Base JIRA URL: $BASE_JIRA_URL

JIRA_PROJECT_ID=`jira_get_project_id $JIRA_PROJECT_NAME`
[ $DEBUG ] && echo Found project id $JIRA_PROJECT_ID for $JIRA_PROJECT_NAME

JIRA_NSP_CUSTOM_FIELD_VULN_ID=`jira_get_custom_field_id $JIRA_NSP_CUSTOM_FIELD_VULN_NAME`
[ $DEBUG ] && echo Found custom field id $JIRA_NSP_CUSTOM_FIELD_VULN_ID for $JIRA_NSP_CUSTOM_FIELD_VULN_NAME

JIRA_NSP_CUSTOM_FIELD_PATH_ID=`jira_get_custom_field_id $JIRA_NSP_CUSTOM_FIELD_PATH_NAME`
[ $DEBUG ] && echo Found custom field id $JIRA_NSP_CUSTOM_FIELD_PATH_ID for $JIRA_NSP_CUSTOM_FIELD_PATH_NAME


for ((i=0;i<$N_VULNS;i++)); do
    TITLE=`cat $JSON_FILE | jq "[$i].title" | tr -d '"'`
    SEVERITY=`cat $JSON_FILE | jq "[$i].cvss_score"| tr -d '"'`
    NSP_VULN_ID=`cat $JSON_FILE | jq "[$i].id"| tr -d '"'`
    MODULE=`cat $JSON_FILE | jq "[$i].module"| tr -d '"'`
    PACKAGE=`cat $JSON_FILE | jq "[$i].path[0] | split(\"@\") | .[0]" | tr -d '"'`
    NSP_PATH=`cat $JSON_FILE | jq "[$i].path | join(\" -> \")" | tr -d '"'`
    SUMMARY="[NSP] ${TITLE/\"/g}: $SEVERITY severity vulnerability found in '$MODULE' for $PACKAGE ($NSP_VULN_ID)"

    jira_create_issue $JIRA_PROJECT_ID "$SUMMARY" "$NSP_VULN_ID" "$NSP_PATH" "$SEVERITY"
done