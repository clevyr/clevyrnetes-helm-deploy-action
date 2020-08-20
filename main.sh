#!/usr/bin/env bash

set -euo pipefail

_log() {
    local IFS=$' \n\t'
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2;
}

cluster_info() {
    gcloud container --project "$host_project" clusters list --format json \
        | jq -r --arg 'key' "$1" '.[][$key]'
}

export IFS=$'\n\t'

# Install yq for parsing helm.yaml
_log Start yq install
GO111MODULE=on go get github.com/mikefarah/yq/v3 >/tmp/yq 2>&1 &
install_pid="$!"

# Activate gcloud auth using specified by GCLOUD_KEY_FILE
_log Activate gcloud auth
gcloud auth activate-service-account --key-file - <<< "$GCLOUD_KEY_FILE"

_log Set local variables
# Set helm url based on default, or use provided HELM_URL variable
helm_url="${HELM_URL:-https://helm.clevyr.cloud}"

# Set the host project based on the value provided or based on the default
host_project="${HOST_PROJECT:-momma-motus}"

# Set the project id based on the key file provided, or use the provided project id
project_id="${GCLOUD_GKE_PROJECT:-$(jq -r .project_id <<< "$GCLOUD_KEY_FILE")}"

# Set the cluster name based on the key file provided unless it is provided
cluster_name="${GCLOUD_CLUSTER_NAME:-$(cluster_info name)}"

# Set the region tag unless it is provided
region="${GCLOUD_REGION:-$(cluster_info zone)}"

# Set the default us gcr docker repo unless another is provided
docker_repo="${REPO_URL:-us.gcr.io/$project_id}"

# Set the environment label based on the last id in the KUBE_NAMESPACE, or use the provided ENV_LABEL variable
environment="${ENV_LABEL:-${KUBE_NAMESPACE##*-}}"

# Set the base folder that contains environment configuration, or use the provided CONFIG_FOLDER variable
config_folder="${CONFIG_FOLDER:-deployment}"

# Set the deployment id to upgrade
deployment="$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}"

# Select kubernetes cluster specified by GCLOUD_CLUSTER_NAME
_log Select Kubernetes cluster
gcloud container clusters get-credentials  \
    "$cluster_name" \
    --region "$region" \
    --project "$host_project"

# Set the kubectl context namespace
_log Set namespace to "$KUBE_NAMESPACE"
kubectl config set-context --current --namespace="$KUBE_NAMESPACE"

# Add custom helm repo
_log Add custom repo
helm repo add clevyr "$helm_url"
helm repo update

# Wait to make sure yq is installed
_log Wait for yq to finish installing
wait "$install_pid" || { cat /tmp/yq && exit 1; }
cat /tmp/yq
export PATH="$PATH:$HOME/go/bin"

framework="$(yq r "$config_folder/$environment/helm.yaml" app.framework)"

# Update helm deployment
_log Begin "clevyr/$framework-chart" upgrade
( set -x && helm upgrade "$deployment" "clevyr/$framework-chart" \
    -f "$config_folder/$environment/helm.yaml" \
    --set "app.image.url=$docker_repo" \
    --set "app.image.tag=$REPO_TAG" \
    --atomic )

# Update static site deployment (if needed)
if yq r -e "$config_folder/$environment/helm.yaml" static.enabled 2>/dev/null; then
  _log Begin clevyr/static-site-helm-chart upgrade
  ( set -x && helm upgrade "$deployment-static-site" clevyr/static-site-helm-chart \
      -f "$config_folder/$environment/helm.yaml" \
      --set "app.image.url=$docker_repo" \
      --set "static.image.tag=$REPO_TAG" \
      --atomic )
fi

# Update redirect deployment (if needed)
if [[ "$(yq r "$config_folder/$environment/helm.yaml" --length redirects)" -gt 0 ]]; then
  _log Begin clevyr/redirect-helm-chart upgrade
  ( set -x && helm upgrade "$deployment-redirects" clevyr/redirect-helm-chart \
      -f "$config_folder/$environment/helm.yaml" \
      --atomic )
fi
