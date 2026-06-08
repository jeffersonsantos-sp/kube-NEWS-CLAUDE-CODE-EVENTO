# AWS — kube-news no EKS

> Infraestrutura ainda não implementada. Esta pasta reserva o espaço para quando a migração AWS for iniciada.

## Estrutura prevista

```
clouds/aws/
├── terraform/    # provisionamento EKS (VPC, nodegroup, IAM)
├── k8s/          # manifestos Blue-Green adaptados (StorageClass: gp3, ELB annotations)
└── argocd/       # Application ArgoCD apontando para clouds/aws/k8s
```

## Diferenças esperadas vs Azure/GCP

| Item | Azure AKS | GCP GKE | AWS EKS |
|---|---|---|---|
| StorageClass | `managed-csi` | `standard-rwo` | `gp2` / `gp3` |
| LB annotations | Azure-specific | Nenhuma (padrão) | `service.beta.kubernetes.io/aws-load-balancer-*` |
| Terraform provider | `azurerm` | `google` | `aws` |
| kubectl context | `AKSCLAUDECODE` | `gke_<proj>_us-central1_*` | `arn:aws:eks:<region>:*` |
