provider "aws" {
  region = "us-east-1"
}

# 1. Access the Availability Zones available in us-east-1
data "aws_availability_zones" "available" {}

# 2. Create the VPC for your Cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "disease-prediction-vpc"
  cidr = "10.0.0.0/16"

  # Use 2 AZs for high availability within the cluster
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # Ensures nodes get a Public IP to connect to the EKS Control Plane
  map_public_ip_on_launch = true
}

# 3. The EKS Cluster (The Brain)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "disease-prediction-cluster"
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # Automatically adds your IAM user as an administrator of the cluster
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      # m7i-flex.large provides 2 vCPU and 8GB RAM 
      # This fixes the "Too many pods" error (ENI limit)
      instance_types = ["m7i-flex.large"]
      ami_type       = "AL2023_x86_64_STANDARD"

      min_size     = 1
      max_size     = 1
      desired_size = 1
    }
  }
}
