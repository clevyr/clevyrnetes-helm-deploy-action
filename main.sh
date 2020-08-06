#!/usr/bin/env bash

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

set -euxo pipefail
export IFS=$'\n\t'

# Install yq for parsing helm.yaml
brew install yq &

# Activate gcloud auth using specified by GCLOUD_KEY_FILE
gcloud auth activate-service-account \
    --key-file - <<< "$GCLOUD_KEY_FILE"

# Set helm url based on default, or use provided HELM_URL variable
default_helm_url="https://helm.clevyr.cloud"
helm_url="${HELM_URL:-$default_helm_url}"

# Set the host project based on the value provided or based on the default
default_host_project="momma-motus"
host_project="${HOST_PROJECT:-$default_host_project}"

# Set the project id based on the key file provided, or use the provided project id
project_id="$(jq -r .project_id <<< "$GCLOUD_KEY_FILE")"
project_id="${GCLOUD_GKE_PROJECT:-$project_id}"

# Set the cluster name based on the key file provided unless it is provided
cluster_name=$(gcloud container --project "$host_project" clusters list --format json \
                | jq '.[]["name"]' \
                | xargs)
cluster_name="${GCLOUD_CLUSTER_NAME:-$cluster_name}"

# Set the region tag unless it is provided
region=$(gcloud container --project "$host_project" clusters list --format json \
          | jq '.[]["zone"]' \
          | xargs)
region="${GCLOUD_REGION:-$region}"

# Set the default us gcr docker repo unless another is provided
docker_repo="us.gcr.io/$project_id"
docker_repo="${REPO_URL:-$docker_repo}"

# Set the environment label based on the last id in the KUBE_NAMESPACE, or use the provided ENV_LABEL variable
environment="${KUBE_NAMESPACE##*-}"
environment="${ENV_LABEL:-$environment}"

# Set the base folder that contains environment configuration, or use the provided CONFIG_FOLDER variable
config_folder="deployment"
config_folder="${CONFIG_FOLDER:-$config_folder}"

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
helm upgrade "$deployment" clevyr/"$(yq r "$config_folder"/"$environment"/helm.yaml 'app.framework')"-chart \
    -f "$config_folder"/"$environment"/helm.yaml \
    --set app.image.url="$docker_repo" \
    --set app.image.tag="$REPO_TAG" \
    --wait
end_update

# Update redirect deployment (if needed)
if [[ $(yq r "$config_folder"/"$environment"/helm.yaml --length 'redirects') -gt 0 ]]; then
  start_update redirect
  helm upgrade "$deployment"-redirects clevyr/redirect-helm-chart \
      -f "$config_folder"/"$environment"/helm.yaml \
      --wait
  end_update
fi
