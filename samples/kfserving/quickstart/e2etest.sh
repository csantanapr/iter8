#!/bin/bash

set -e -x

export EXPERIMENT=quickstart-exp

# cleanup () {
#     status=$?
#     if (( $status != 0 )); then
#         kind delete cluster
#         echo -e "\033[0;31mFAILED:\033[0m $0"
#     fi
#     exit $status
# }
# trap "cleanup" EXIT

# create cluster
kind create cluster
kubectl cluster-info --context kind-kind

# platform setup
echo "Setting up platform"
$ITER8/samples/kfserving/quickstart/platformsetup.sh

echo "Create app/ML model versions"
kubectl apply -f $ITER8/samples/kfserving/quickstart/baseline.yaml
kubectl apply -f $ITER8/samples/kfserving/quickstart/candidate.yaml
kubectl apply -f $ITER8/samples/kfserving/quickstart/routing-rule.yaml
kubectl wait --for=condition=Ready isvc/flowers -n ns-baseline --timeout=600s       
kubectl wait --for=condition=Ready isvc/flowers -n ns-candidate --timeout=600s

echo "Define metrics"
kubectl apply -f $ITER8/samples/kfserving/quickstart/metrics.yaml

echo "Launch experiment"
kubectl apply -f $ITER8/samples/kfserving/quickstart/experiment.yaml

echo "Generate requests"

URL_VALUE="http://$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.clusterIP}'):80/productpage"

# Port-forward Istio ingress
INGRESS_GATEWAY_SERVICE=$(kubectl get svc -n istio-system --selector="app=istio-ingressgateway" --output jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n istio-system svc/${INGRESS_GATEWAY_SERVICE} 8080:80 &

# Get the prediction payload
curl -o /tmp/input.json https://raw.githubusercontent.com/kubeflow/kfserving/master/docs/samples/v1beta1/rollout/input.json

# Send prediction requests... this step requires fortio
fortio load -t 360s -qps 4.0 -H "Host: example.com" -payload-file /tmp/input.json -json /tmp/fortiooutput.json http://localhost:8080/v1/models/flowers:predict

# Wait
kubectl wait experiment $EXPERIMENT --for=condition=Completed --timeout=300s

# Log final experiment
kubectl get experiment $EXPERIMENT -o yaml

# Check
source $ITER8/samples/kfserving/quickstart/check.sh

kubectl delete -f $ITER8/samples/kfserving/quickstart/experiment.yaml
# Cleanup .. delete inference services (and its ns takes forever)...
# so skipping this for now... need to be fixed later;
# possibly by bringing this up with KFServing

# kubectl delete -f $ITER8/samples/kfserving/quickstart/baseline.yaml
# kubectl delete -f $ITER8/samples/kfserving/quickstart/candidate.yaml

# delete cluster
kind delete cluster

set +e

echo -e "\033[0;32mSUCCESS:\033[0m $0"
