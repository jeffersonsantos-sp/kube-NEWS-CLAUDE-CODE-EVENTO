variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "kube-news-gke"
}

variable "node_count" {
  description = "Number of nodes per zone in the default node pool"
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "GCE machine type for GKE nodes"
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for each node"
  type        = number
  default     = 30
}

variable "kubernetes_version" {
  description = "Kubernetes version — use 'latest' or a specific channel release"
  type        = string
  default     = "latest"
}
