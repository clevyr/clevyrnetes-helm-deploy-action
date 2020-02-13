set -euxo pipefail

# Create a file with the kubeconfig
echo $KUBECONFIGB64 | base64 -d > .kubeconfig
export KUBECONFIG=.kubeconfig

# Push update to application through helm
kubectl set image deployments/$CHART_TITLE $CHART_TITLE=$REPO_URL:$REPO_TAG

# Delete the kubeconfig file
rm .kubeconfig