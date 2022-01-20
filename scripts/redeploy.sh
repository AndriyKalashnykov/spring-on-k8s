#!/bin/bash

set -x

git cmp "updated accelerator"

KC=~/.kube/config

export KUBECONFIG=$KC

#SRV_SVC=$(kubectl get service -n accelerator-system acc-server | sed -n '2 p' | awk '{print $4}')
#CNT=$(tanzu acc list --server-url=http://$SRV_SVC | awk '{print $4}' | grep -wc spring-on-k8s)
#if [ $CNT -gt 0 ]
#then
#  tanzu acc delete spring-on-k8s --kubeconfig $KC
#fi
#tanzu acc create spring-on-k8s --kubeconfig $KC  --git-repository https://github.com/AndriyKalashnykov/spring-on-k8s.git --git-branch main

kubectl delete -f  ~/projects/spring-on-k8s/k8s-resource.yaml --namespace accelerator-system
kubectl apply -f  ~/projects/spring-on-k8s/k8s-resource.yaml --namespace accelerator-system

kubectl get accelerator --namespace accelerator-system

