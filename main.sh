#!/usr/bin/env bash

# Set helm url based on default, or use provided HELM_URL variable
default_helm_url="https://helm.clevyr.cloud"
HELM_URL=${HELM_URL:-$default_helm_url}

# Install yq for parsing helm.yaml
brew install yq

set -euxo pipefail

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
helm upgrade "$deployment" clevyr/"$(yq r kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml 'app.framework')"-chart \
    -n "$KUBE_NAMESPACE" \
    -f kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml \
    --set app.image.url="$REPO_URL" \
    --set app.image.tag="$REPO_TAG"

# Update redirect deployment (if needed)
if [[ $(yq r kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml --length 'redirects') -gt 0 ]]; then
  helm upgrade "$deployment"-redirects clevyr/redirect-helm-chart \
      -n "$KUBE_NAMESPACE" \
      -f kubernetes/"${KUBE_NAMESPACE##*-}"/helm.yaml
fi
