#!/usr/bin/env bash

set -euxo pipefail

# Create a file with the Google Cloud Auth Key File
gcloud auth activate-service-account \
    --key-file - <<< "$GCLOUD_KEY_FILE"

project_id="$(jq -r .project_id <<< "$GCLOUD_KEY_FILE")"
project_id=${GCLOUD_GKE_PROJECT:-$project_id}

gcloud container clusters get-credentials \
    "$GCLOUD_CLUSTER_NAME" \
    --region "$GCLOUD_REGION" \
    --project "$project_id"

# Set the deployment id to upgrade
deployment="$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}"

pwd
ls

# Push update to application through kubectl
kubectl -n "$KUBE_NAMESPACE" set image "deployments/$deployment" "*=$REPO_URL:$REPO_TAG"

if ! kubectl -n "$KUBE_NAMESPACE" rollout status --timeout="${DEPLOY_TIMEOUT:-2m}" deployment "$deployment"; then
    kubectl -n "$KUBE_NAMESPACE" rollout undo deployment "$deployment"
    exit 1
fi
