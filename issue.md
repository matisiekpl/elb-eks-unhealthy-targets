**DISCLAIMER: This bug was previously issued in https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/3979, but due to business priorities company does not have workforce to supply reproduction code.** This issue is a followup to it, with link to code: https://github.com/matisiekpl/elb-eks-unhealthy-targets/

**Bug Description**
I'm trying to deploy web application with pretty standard stack, that contains deployment, service and ingress. We are using 3 worker nodes on EKS, and when I scale replicas to at least 2, Load Balancer UI shows that targets randomly goes unhealthy. Also app responds with 504 Gateway timed out every few requests. It seems that traffic goes only to one pod/worker node, completely ignoring routing to other pods on other nodes.

Worth to notice is that in ALB UI shows that statuses of targets are some kind of random. In one moment all targets are healthy, after refresh only one node is healthy. After second refresh to of them are healthy, with one unhealthy. At least one node is always healthy, as this is the worker that responds for successful requests.

**Steps to Reproduce**
Check following repository: https://github.com/matisiekpl/elb-eks-unhealthy-targets
It contains full instructions how to reproduce bug in `us-west-1`. Especially take a look at `setup.sh`

**Expected Behavior**
- `curl` should report 200 response codes for each request
- ALB Web Console should report that all three targets are healthy.

**Actual Behavior**
- Some requests are returned correctly instantly, but some of them are timing out returning 504 (~10% of them).
- ALB Web Console reports that ALB targets randomly go unhealthy. There are moments where all targets are healthy. Also, there are moments where all targets are unhealthy. Most of the time 1–2 nodes of out three are unhealthy.

**Regression**
No

**Current Workarounds**
No workarounds available

**Environment**
- AWS Load Balancer controller version: v2.13.1
- Kubernetes version: 1.31
- Using EKS (yes/no), if so version?: eks.25
- Using Service or Ingress: Ingress
- AWS region: us-west-1
- How was the aws-load-balancer-controller installed:
    - If helm was used then please show output of `helm ls -A | grep -i aws-load-balancer-controller`
    - If helm was used then please show output of `helm -n <controllernamespace> get values <helmreleasename>`
    - If helm was not used, then copy/paste the exact command used to install the controller, including flags and options.
- Current state of the Controller configuration:
    - `kubectl -n <controllernamespace> describe deployment aws-load-balancer-controller`
- Current state of the Ingress/Service configuration:
    - `kubectl describe ingressclasses`
    - `kubectl -n <appnamespace> describe ingress <ingressname>`
    - `kubectl -n <appnamespace> describe svc <servicename>`

**Possible Solution (Optional)**
No idea

**Contribution Intention (Optional)**
- [ ] Yes, I'm willing to submit a PR to fix this issue
- [x] No, I cannot work on a PR at this time

**Additional Context**
<!---Add any other context about the problem here.-->
