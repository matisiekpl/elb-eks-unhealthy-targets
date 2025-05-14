#!/bin/bash

mv installed.tf installed.tf.disabled
terraform apply -auto-approve
aws eks update-kubeconfig --name cluster-bug --region us-west-1
kubectl delete configmap aws-auth -n kube-system # Will be installed from installed.tf
mv installed.tf.disabled installed.tf
terraform apply -auto-approve