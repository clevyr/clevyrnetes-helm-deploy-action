#!/usr/bin/env bash

set -euxo pipefail

# Create a file with the Google Cloud Auth Key File
gcloud auth activate-service-account \
    --key-file - <<< $GCLOUD_KEY_FILE

gcloud container clusters get-credentials \
    $GCLOUD_CLUSTER_NAME \
    --region $GCLOUD_REGION

# Push update to application through helm
kubectl set image \
    deployments/$CHART_TITLE \
    $CHART_TITLE=$REPO_URL:$REPO_TAG

