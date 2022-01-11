#!/bin/bash

set -x

export KUBECONFIG=~/.kube/config
SRV_SVC=$(kubectl get service -n accelerator-system acc-server| sed -n '2 p' | awk '{print $4}')


CNT=$(tanzu acc list --server-url=http://$SRV_SVC } | grep -wc spring-on-k8s)

if [ $CNT -eq 1 ]
then
    tanzu acc delete spring-on-k8s
fi


tanzu acc create spring-on-k8s --git-repository https://github.com/AndriyKalashnykov/spring-on-k8s.git --git-branch main