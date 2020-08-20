#!/usr/bin/env bash

set -euo pipefail

start_update() {
  set +x
  printf "\nUpdating %s chart\n\n" "$1" 
  set -x
}

end_update() {
  set +x
  printf "\nUpdate complete\n\n"
  set -x
}

cluster_info() {
    gcloud container --project "$host_project" clusters list --format json \
        | jq -r --arg 'key' "$1" '.[][$key]'
}

export IFS=$'\n\t'

# Install yq for parsing helm.yaml
brew install --quiet yq &

# Activate gcloud auth using specified by GCLOUD_KEY_FILE
gcloud auth activate-service-account --key-file - <<< "$GCLOUD_KEY_FILE"

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

set -x

# Select kubernetes cluster specified by GCLOUD_CLUSTER_NAME
gcloud container clusters get-credentials  \
    "$cluster_name" \
    --region "$region" \
    --project "$host_project"

# Set the kubectl context namespace
kubectl config set-context --current --namespace="$KUBE_NAMESPACE"

# Set the deployment id to upgrade
deployment="$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}"

# Add custom helm repo
helm repo add clevyr "$helm_url"
helm repo update

# Wait to make sure yq is installed
wait

# Update helm deployment
start_update main
helm upgrade "$deployment" "clevyr/$(yq r "$config_folder/$environment/helm.yaml" app.framework)-chart" \
    -f "$config_folder/$environment/helm.yaml" \
    --set "app.image.url=$docker_repo" \
    --set "app.image.tag=$REPO_TAG" \
    --atomic
end_update

# Update static site deployment (if needed)
if [[ "$(yq r "$config_folder/$environment/helm.yaml" static.enabled)" = 'true' ]]; then
  start_update static-site
  helm upgrade "$deployment-static-site" clevyr/static-site-helm-chart \
      -f "$config_folder/$environment/helm.yaml" \
      --set "app.image.url=$docker_repo" \
      --set "static.image.tag=$REPO_TAG" \
      --atomic
  end_update
fi

# Update redirect deployment (if needed)
if [[ $(yq r "$config_folder/$environment/helm.yaml" --length 'redirects') -gt 0 ]]; then
  start_update redirect
  helm upgrade "$deployment-redirects" clevyr/redirect-helm-chart \
      -f "$config_folder/$environment/helm.yaml" \
      --atomic
  end_update
fi
