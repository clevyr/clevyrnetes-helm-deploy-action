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

# Push update to application through kubectl
kubectl -n "$KUBE_NAMESPACE" set image "deployments/$KUBE_NAMESPACE${DEPLOYMENT_MODIFIER:+-$DEPLOYMENT_MODIFIER}" "*=$REPO_URL:$REPO_TAG"

if ! kubectl -n "$KUBE_NAMESPACE" rollout status --timeout="${DEPLOY_TIMEOUT:-2m}" deployment "$KUBE_NAMESPACE"; then
    kubectl -n "$KUBE_NAMESPACE" rollout undo deployment "$KUBE_NAMESPACE"
    exit 1
fi
