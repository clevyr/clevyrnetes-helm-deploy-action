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
HELM_URL="${HELM_URL:-$default_helm_url}"

# Set the project id based on the key file provided, or use the provided project id
project_id="$(jq -r .project_id <<< "$GCLOUD_KEY_FILE")"
project_id="${GCLOUD_GKE_PROJECT:-$project_id}"

# Set the environment label based on the last id in the KUBE_NAMESPACE, or use the provided ENV_LABEL variable
environment="${KUBE_NAMESPACE##*-}"
environment="${ENV_LABEL:-$environment}"

# Set the base folder that contains environment configuration, or use the provided CONFIG_FOLDER variable
config_folder="deployment"
config_folder="${CONFIG_FOLDER:-$config_folder}"

# Select kubernetes cluster specified by GCLOUD_CLUSTER_NAME
gcloud container clusters get-credentials \
    "$GCLOUD_CLUSTER_NAME" \
    --region "$GCLOUD_REGION" \
    --project "$project_id"

# Set the kubectl context namespace
kubectl config set-context --current --namespace="$KUBE_NAMESPACE"

# Set the deployment id to upgrade
deployment="$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}"

# Add custom helm repo
helm repo add clevyr "$HELM_URL"
helm repo update

# Wait to make sure yq is installed
wait

# Update helm deployment
start_update main
helm upgrade "$deployment" clevyr/"$(yq r "$config_folder"/"$environment"/helm.yaml 'app.framework')"-chart \
    -f "$config_folder"/"$environment"/helm.yaml \
    --set app.image.url="$REPO_URL" \
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
