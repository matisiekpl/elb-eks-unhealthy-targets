# ALB Bug Reproduction instruction

```bash
mv installed.tf installed.tf.disabled
terraform apply -auto-approve
kubectl eks update-kubeconfig --name cluster-bug
kubectl delete configmap aws-auth -n kube-system # Will be installed from installed.tf
mv installed.tf.disabled installed.tf
terraform apply -auto-approve

# Get <ALB_DNS_NAME> from AWS Console
for i in `seq 1 100`; do curl -H 'Host: example.customdomain.com' <ALB_DNS_NAME>; done
```