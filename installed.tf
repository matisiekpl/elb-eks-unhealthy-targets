provider "kubernetes" {
  host = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# # AWS Auth Configuration
resource "kubernetes_config_map" "aws_auth" {
  data = {
    "mapRoles" = <<-EOT
                - groups:
                  - system:bootstrappers
                  - system:nodes
                  rolearn: arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-nodegroup-role
                  username: system:node:{{EC2PrivateDNSName}}
            EOT
    "mapUsers" = join("", [local.user_role_mapping])
  }

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
}

# EBS Storage Class
resource "kubernetes_storage_class" "ebs" {
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  metadata {
    name = "ebs-sc"
  }

  parameters = {
    "type"                      = "gp2"
    "csi.storage.k8s.io/fstype" = "xfs"
    "encrypted"                 = "true"
  }

  allowed_topologies {
    match_label_expressions {
      key = "topology.ebs.csi.aws.com/zone"
      values = [
        "us-west-1a",
        "us-west-1b",
      ]
    }
  }
}

# CSI Secret Store
resource "helm_release" "csi_secret_store" {
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  name       = "csi-secrets-store"
  namespace  = "kube-system"
  version    = "1.5.0"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  set {
    name  = "enableSecretRotation"
    value = "true"
  }

  set {
    name  = "rotationPollInterval"
    value = "2m"
  }

  set {
    name  = "metrics.enabled"
    value = "true"
  }

  set {
    name  = "tokenRequests.audience"
    value = "sts.amazonaws.com"
  }
}

# CSI Secret Store AWS Provider
data "http" "csi_secret_store_aws_provider_manifest" {
  url = "https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/14e3900554f65268ab839b054ec2d999dae357c8/deployment/aws-provider-installer.yaml"
}

resource "kubernetes_manifest" "csi_secret_store_aws_provider" {
  for_each = {
    for idx, manifest in
    local.csi_secret_store_aws_provider_manifests : idx => manifest if trim(manifest, " \n") != ""
  }
  manifest = yamldecode(each.value)

  computed_fields = ["spec.template.spec.hostNetwork"]

  depends_on = [helm_release.csi_secret_store]
}

# AWS Load Balancer Controller
module "load_balancer_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "bug-eks-load-balancer"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_service_account" "load_balancer_service_account" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn"               = module.load_balancer_role.iam_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  depends_on = [
    kubernetes_service_account.load_balancer_service_account
  ]

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "clusterName"
    value = "cluster-bug"
  }
}

# EKS IAM Cluster Role
data "http" "eks_iam_cluster_role_manifest" {
  url = "https://s3.us-west-2.amazonaws.com/amazon-eks/docs/eks-console-full-access.yaml"
}

resource "kubernetes_manifest" "eks_iam_cluster_role" {
  for_each = zipmap(range(0, length(local.eks_iam_cluster_role_manifests)), local.eks_iam_cluster_role_manifests)
  manifest = yamldecode(each.value)
}

# Locals
locals {
  user_role_mapping = join("\n", [
    for user in ["mateusz.wozniak"] : <<-EOT
                - userarn: arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${user}
                  username: ${user}
                  groups:
                    - eks-console-dashboard-full-access-group
                    - system:masters
                - userarn: arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${user}-api
                  username: ${user}-api
                  groups:
                    - eks-console-dashboard-full-access-group
                    - system:masters
            EOT
  ])
  eks_iam_cluster_role_manifests = split("---", data.http.eks_iam_cluster_role_manifest.response_body)
  csi_secret_store_aws_provider_manifests = split("---", data.http.csi_secret_store_aws_provider_manifest.response_body)
}

# Example app
resource "kubernetes_namespace" "app" {
  metadata {
    name = "example"
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "app-example"
    namespace = "example"
    labels = {
      app                          = "app-example"
      "tags.datadoghq.com/service" = "app"
      "tags.datadoghq.com/env"     = "bug"
      "tags.datadoghq.com/version" = "latest"
    }
  }

  spec {
    replicas = 6

    selector {
      match_labels = {
        app = "app-example"
      }
    }

    template {
      metadata {
        labels = {
          app                          = "app-example"
          "tags.datadoghq.com/service" = "app"
          "tags.datadoghq.com/env"     = "bug"
          "tags.datadoghq.com/version" = "latest"
        }

        annotations = {
          "ad.datadoghq.com/app.logs"         = "[{\"source\":\"kubernetes\",\"service\":\"app\"}]"
          "ad.datadoghq.com/app.check_names"  = "[\"openmetrics\"]"
          "ad.datadoghq.com/app.init_configs" = "[{}]"
          "ad.datadoghq.com/app.instances"    = <<-EOT
            [{
              "prometheus_url": "http://%%host%%:80/metrics/",
              "namespace": "llm_api",
              "metrics": [".*"]
            }]
          EOT
          "rollme" = timestamp()
        }
      }

      spec {
        service_account_name = "app-example"

        container {
          name  = "app"
          image = "nginx:latest"

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 90
          }

          port {
            container_port = 80
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "app" {
  metadata {
    name      = "app-example"
    namespace = "example"
    labels = {
      app = "app-example"
    }
  }

  spec {
    selector = {
      app = "app-example"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }

    type = "NodePort"
  }
}

resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "app-example"
    namespace = "example"

    annotations = {
      "kubernetes.io/ingress.class"                        = "alb"
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/group.name"               = "main"
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/load-balancer-name"       = "lb-eks-bug"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=3600"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = "example.customdomain.com"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "app-example"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account" "app" {
  metadata {
    name      = "app-example"
    namespace = "example"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_services_access.arn
    }
  }
}
