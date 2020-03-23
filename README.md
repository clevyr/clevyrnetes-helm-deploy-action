# kubernetes-deploy-action
This repo accepts a helm value file, chart title, and image tag for the clevyr-cloud 
helm chart and updates the resource in kubernetes.

## Prerequisites
In order for this repo to properly 

## Environment Variables

| Variable            | Details                                                                                 | Example                                       |
|---------------------|-----------------------------------------------------------------------------------------|-----------------------------------------------|
| CHART_TITLE         | The chart that was deployed associated with the resource stack that is getting updated. | `clevyr-com`                                  |
| REPO_URL            | The docker repository to pull for the deployment image.                                 | `us.gcr.io/motus-k8s-cluster/clevyr-com`      |
| REPO_TAG            | The tag of the image to pull for the deployment image.                                  | `latest`                                      |
| GCLOUD_CLUSTER_NAME | The cluster name to activate credentials for.                                           | `motus-cluster`                               |
| GCLOUD_REGION       | The location of the cluster.                                                            | `us-central1`                                 |
| GCLOUD_KEY_FILE     | The JSON of the key-file to authenticate to Google Cloud.                               | `{"type":"service_account","project_id":...}` |
| KUBE_NAMESPACE      | The namespace to deploy to.                                                             | `clevyr-com-dev`                              |
| DEPLOY_TIMEOUT      | The timeout that is passed to `kubectl rollout`.                                        | `2m`                                          |
| DEPLOYMENT_MODIFIER | The optional tag for the deployment to modify                                           | `nil`
