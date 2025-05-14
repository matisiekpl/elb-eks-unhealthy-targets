# ALB Bug Reproduction instruction

This repo demonstrates the AWS EKS ELB Controller bug related to unhealthy targets.

- File `cluster.tf` creates basic AWS EKS cluster in `us-west-1`.
- File `installed.tf` installs required resources such as ELB and CSI drivers and example nginx app called `example` (it
  is supposed to apply this file AFTER creation of cluster).

How to launch this reproducible setup?

1. Run `setup.sh`
2. Wait a few minutes
3. Grab DNS Endpoint from ALB from AWS Console
4. Make ~200 curls every second to this endpoint or fill endpoint in `measure.js` and run it.

Expected results:
User should see 200 response codes for each request
ALB Web Console should report that all three targets are healthy.

Actual results:
Some requests are returned correctly instantly, but some of them are timing out returning 504 (~10% of them).
ALB Web Console reports that ALB targets randomly go unhealthy. There are moments where all targets are healthy. Also,
there are moments where all targets are unhealthy. Most of the time 1–2 nodes of out three are unhealthy.