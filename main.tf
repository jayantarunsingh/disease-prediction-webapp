terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
    helm = {
      source  = "hashicorp/helm"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ==============================================================================
# 1. VPC CONFIGURATION
# ==============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "disease-prediction-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # FIX 1: This is strictly required by AWS for EKS nodes in public subnets
  map_public_ip_on_launch = true
}

# ==============================================================================
# 2. EKS CLUSTER CONFIGURATION
# ==============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "disease-prediction-cluster"
  cluster_version = "1.30"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 2
      desired_size = 1
      # FIX 2: Restored your original instance type
      instance_types = ["m7i-flex.large"]
    }
  }

  enable_cluster_creator_admin_permissions = true
}

# ==============================================================================
# 3. KUBERNETES & HELM PROVIDERS
# ==============================================================================
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# ==============================================================================
# 4. PROMETHEUS & ALERTMANAGER
# ==============================================================================
resource "helm_release" "prometheus" {
  name             = "monitoring"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  
  depends_on = [module.eks]

  values = [
    jsonencode({
      grafana = {
        adminPassword = "admin123"
        sidecar = { dashboards = { enabled = true, searchNamespace = "ALL" } }
      }
      additionalPrometheusRulesMap = {
        custom-alerts = {
          groups = [{
            name = "disease-app-alerts"
            rules = [
              {
                alert = "HighCpuUsage"
                expr  = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[2m])) * 100) > 80"
                for   = "2m"
                labels = { severity = "critical" }
                annotations = { summary = "High CPU on {{ $labels.instance }}", description = "CPU usage is above 80% on your AWS Node." }
              },
              {
                alert = "DiseaseAppDown"
                expr  = "up{job=\"disease-prediction-service\"} == 0"
                for   = "1m"
                labels = { severity = "critical" }
                annotations = { summary = "Disease Prediction App is DOWN", description = "The Flask web server is unreachable." }
              }
            ]
          }]
        }
      }
      alertmanager = {
        config = {
          global = {
            smtp_smarthost     = "smtp.gmail.com:587"
            smtp_from          = "singhjayant308@gmail.com"
            smtp_auth_username = "singhjayant308@gmail.com"
            smtp_auth_password = "xvjaanawdvfcxomq" # <--- PASTE PASSWORD HERE
          }
          route = { 
            receiver = "email-notifications"
            group_by = ["namespace"]
            # We must include this to keep Kubernetes happy!
            routes = [
              {
                receiver = "null"
                matchers = ["alertname=\"Watchdog\""]
              }
            ]
          }
          receivers = [
            {
              name = "null" # The dummy receiver for Watchdog
            },
            {
              name = "email-notifications"
              email_configs = [{ to = "singhjayant308@gmail.com" }]
            }
          ]
        }
      }
    })
  ]
}
# ==============================================================================
# 5. SERVICE MONITOR
# ==============================================================================
resource "kubernetes_manifest" "disease_prediction_monitor" {
  depends_on = [helm_release.prometheus]

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "disease-prediction-monitor"
      namespace = "monitoring"
      labels    = { release = "monitoring" }
    }
    spec = {
      namespaceSelector = { matchNames = ["default"] }
      selector = { matchLabels = { app = "disease-prediction" } }
      endpoints = [{ port = "http", interval = "30s" }]
    }
  }
}
