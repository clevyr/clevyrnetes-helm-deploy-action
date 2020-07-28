#!/usr/bin/env bash

HELM_URL="https://helm.clevyr.cloud"

set -euxo pipefail

# Install yq for parsing helm.yaml
brew install yq

# Activate gcloud auth using specified by GCLOUD_KEY_FILE
gcloud auth activate-service-account \
    --key-file - <<< "$GCLOUD_KEY_FILE"

# Set the project id based on the key file provided, or use the provided project id
project_id="$(jq -r .project_id <<< "$GCLOUD_KEY_FILE")"
project_id=${GCLOUD_GKE_PROJECT:-$project_id}

# Select kubernetes cluster specified by GCLOUD_CLUSTER_NAME
gcloud container clusters get-credentials \
    "$GCLOUD_CLUSTER_NAME" \
    --region "$GCLOUD_REGION" \
    --project "$project_id"

# Set the deployment id to upgrade
deployment="$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}"

# Add custom helm repo
helm repo add --username "$HELM_USER" --password "$HELM_PASS" clevyr "$HELM_URL"
helm repo update

# Update helm deployment
helm upgrade "$deployment" clevyr/"$(cat kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml | yq -r '.app.framework' -)"-chart \
    -f kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml \
    --set app.image.url="$REPO_URL" \
    --set app.image.tag="$REPO_TAG"

# Update redirect deployment (if needed)
if [[ $(yq '.redirects | length' kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml) -gt 0 ]]; then
  helm upgrade "$deployment"-redirects clevyr/redirect-helm-chart \
      -f kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml
fi
