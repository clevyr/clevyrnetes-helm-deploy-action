#!/usr/bin/env bash

set -euo pipefail
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

if [[ "${RUNNER_DEBUG:-}" == "1" ]]; then
    set -x
fi

_log() {
    local IFS=$' \n\t'
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2;
}

abort_temp_build() {
    _log "$@"
    echo '::set-output name=skipped::true'
    exit 0
}

deploy_chart() {
    local chart="$1" \
        modifier="${2:+-$2}"
    _log Begin "$chart" upgrade
     flags=( upgrade "$deployment$modifier" "$chart" \
            -f "$config_folder/$environment/helm.yaml" \
            --set "app.image.url=$docker_repo" \
            --set "app.image.tag=$REPO_TAG" \
            --set "static.image.tag=$REPO_TAG" \
            --atomic --timeout "${HELM_TIMEOUT:-5m}" )
    if [ -f "$config_folder/$environment/secrets.yaml" ]; then
        flags+=( -f "$config_folder/$environment/secrets.yaml" )
    fi
set -x && helm secrets "${flags[@]}"
}

get_deployment_url() {
    grep -E '::set-output name=app_url::' <<< "$1" | sed -E 's/.*::(.*)/\1/'
}

create_deployment() {
    local params
    params="$(jq -nc \
        --arg ref "$GITHUB_SHA" \
        --arg environment "$environment" \
        '{
            "ref": $ref,
            "environment": $environment,
            "auto_merge": false,
            "required_contexts": [],
            "production_environment": $environment | startswith("prod")
        }')"

    gh api -X POST "/repos/:owner/:repo/deployments" \
        -H 'Accept: application/vnd.github.ant-man-preview+json' \
        --input - <<< "$params" || true
}

set_deployment_status() {
    if [[ -n "${deployment_id:-}" ]]; then
        local state="$1" \
            environment_url="${2:-}"
        gh api --silent -X POST "/repos/:owner/:repo/deployments/$deployment_id/statuses" \
            -H 'Accept: application/vnd.github.ant-man-preview+json' \
            -H 'Accept: application/vnd.github.flash-preview+json' \
            -F "state=$state" \
            -F "log_url=https://github.com/$GITHUB_REPOSITORY/commit/$GITHUB_SHA/checks" \
            -F "environment_url=$environment_url" \
            -F 'auto_inactive=true' || true
    fi
}

export IFS=$'\n\t'
tempBuild="${TEMP_BUILD:-false}"

_log Set local variables
# Set helm url based on default, or use provided HELM_URL variable
helm_url="${HELM_URL:-https://helm.clevyr.cloud}"

# Set the project id based on the key file provided, or use the provided project id
project_id="${GCLOUD_GKE_PROJECT:-$(jq -r .project_id <<< "$GCLOUD_KEY_FILE")}"

# Set the default us gcr docker repo unless another is provided
docker_repo="${REPO_URL:-us.gcr.io/$project_id}"

### TEMP BUILD SECTION 1
if [ $tempBuild == "true" ]; then
    prNum="$(gh pr view --json number,state -q 'select(.state=="OPEN") | .number' || true)"
    if [ -z "${prNum:-}" ]; then
        abort_temp_build 'Not operating on a branch with a PR, exiting.'
    fi
    _log Verify tempbuilds folder exists
    if [ ! -d deployment/tempbuilds ]; then
        abort_temp_build 'tempbuilds folder not found, exiting.'
    fi
    _log Verify the target namespace exists
    appName=$(< deployment/application_name)
    if ! kubectl get namespace $appName-pr$prNum ; then
        abort_temp_build 'Target namespace does not exist, exiting.'
    fi

    _log Setting name-based variables
    KUBE_NAMESPACE=$appName-pr$prNum
fi
### END TEMP BUILD SECTION 1

# Set the environment label based on the last id in the KUBE_NAMESPACE, or use the provided ENV_LABEL variable
environment="${ENV_LABEL:-${KUBE_NAMESPACE##*-}}"

# Set the base folder that contains environment configuration, or use the provided CONFIG_FOLDER variable
config_folder="${CONFIG_FOLDER:-deployment}"

# Set the deployment id to upgrade
deployment="$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    # Create the deployment
    github_deployment="$(create_deployment)"

    # Set the deployment status
    deployment_id="$(jq '.id' <<< "$github_deployment")"
    set_deployment_status in_progress
    trap 'set_deployment_status failure' ERR
fi

# Set the kubectl context namespace
_log Set namespace to "$KUBE_NAMESPACE"
kubectl config set-context --current --namespace="$KUBE_NAMESPACE"

# Install helm secrets
helm plugin install https://github.com/jkroepke/helm-secrets --version v3.8.1

# Add custom helm repo
_log Add custom repo
helm repo add clevyr "$helm_url"
helm repo update

### MORE TEMPBUILD STUFF
if [ $tempBuild == "true" ]; then
    _log Copying tempbuild folder
    mv $config_folder//tempbuilds $config_folder//$environment

    _log Pulling previous URL and updating tempbuilds helm.yaml
    friendlyName=$(helm get values $deployment | yq e .app.ingress.hostname - | sed "s/$(yq e .app.ingress.hostname $config_folder/$environment/helm.yaml | sed 's/REPLACE//g')//g")
    sed -i "s/REPLACE/$friendlyName/g" $config_folder/$environment/helm.yaml
fi

### END TEMPBUILD SECTION

framework="$(yq e '.app.framework' "$config_folder/$environment/helm.yaml")"

# Update helm deployment
notes="$(deploy_chart "clevyr/$framework-chart")"
echo "$notes"
environment_url="$(get_deployment_url "$notes")"

# Update static site deployment (if needed)
if yq e -e '.static.enabled' "$config_folder/$environment/helm.yaml" >/dev/null 2>&1; then
    notes="$(deploy_chart clevyr/static-site-helm-chart static-site)"
    echo "$notes"
    environment_url="$(get_deployment_url "$notes")"
fi

# Update redirect deployment (if needed)
if [[ "$(yq e '.redirects | length' "$config_folder/$environment/helm.yaml")" -gt 0 ]]; then
    deploy_chart clevyr/redirect-helm-chart redirects
fi

# Update websocket deployment (if needed)
if [[ -f "$config_folder"/"$environment"/websocket.yaml ]]; then
  chart="clevyr/laravel-websocket-chart"
  _log Begin "$chart" upgrade
  helm upgrade "$deployment"-websocket "$chart" \
      -f "$config_folder"/"$environment"/websocket.yaml \
      -f "$config_folder"/"$environment"/helm.yaml \
      --wait
fi

set_deployment_status success "$environment_url"
