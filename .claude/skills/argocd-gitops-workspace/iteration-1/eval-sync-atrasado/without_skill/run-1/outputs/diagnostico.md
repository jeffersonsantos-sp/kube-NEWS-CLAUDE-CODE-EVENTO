# Diagnóstico: ArgoCD não sincronizando após git tag v2.0.0

**Data:** 2026-06-03  
**Cluster:** AKSCLAUDECODE  
**Namespace ArgoCD:** argocd  
**Namespace App:** kube-news

---

## Resumo Executivo

O ArgoCD **não** está com problema de sincronização. Ele está funcionando corretamente, sincronizado com o branch `main` no commit `ae0267c5`. O problema real é diferente: **a tag `v2.0.0` não mudou nenhum arquivo de manifesto no branch `main`**. Como o ArgoCD está configurado para rastrear `targetRevision: main` (não uma tag), ele só sincroniza quando o conteúdo dos manifestos em `k8s/` no branch `main` muda. Criar uma tag git não altera o conteúdo do branch, portanto o ArgoCD não tem nada para sincronizar.

---

## Estado Atual do Cluster

### ArgoCD Application: kube-news
| Campo | Valor |
|---|---|
| Sync Status | **Synced** |
| Health Status | **Healthy** |
| Target Revision | `main` |
| Último Commit Sincronizado | `ae0267c5771973ec7e6a49729421b772d34093d1` |
| Último Sync | 2026-06-03T20:55:16Z (sync manual pelo admin) |
| Repo URL | `https://github.com/jeffersonsantos-sp/kube-NEWS-CLAUDE-CODE-EVENTO.git` |
| Path | `k8s/` |

### Deployments em execução no cluster (namespace kube-news)
| Deployment | Imagem em execução | Status |
|---|---|---|
| kube-news-blue | `updateinformatica/claude-devops:1.0` | 2/2 Running |
| kube-news-green | `updateinformatica/claude-devops:v1.2.6` | 2/2 Running |
| postgres | `postgres:15-alpine` | 1/1 Running |

### O que dizem os manifestos no repo (branch main)
| Arquivo | Imagem declarada |
|---|---|
| `k8s/kube-news-blue.yaml` | `updateinformatica/claude-devops:v1.2.6` |
| `k8s/kube-news-green.yaml` | `updateinformatica/claude-devops:v1.2.5` |

**Observação importante:** Há uma divergência entre o manifesto `kube-news-blue.yaml` (declara `v1.2.6`) e o que está rodando no cluster (imagem `1.0`). Isso indica que o manifesto no arquivo local foi editado mas não foi o que o ArgoCD aplicou — o ArgoCD aplicou `v1.2.6` para o green e `1.0` para o blue conforme o sync histórico (`ae0267c5`).

---

## Causa Raiz do Problema de Sincronização do v2.0.0

### Por que a nova imagem v2.0.0 não apareceu no cluster

**Causa:** O workflow GitOps não foi completado. Criar uma tag git (`git tag v2.0.0 && git push --tags`) **não é suficiente** para que o ArgoCD faça deploy da nova imagem. A tag cria um ponteiro para um commit, mas não altera o conteúdo dos arquivos YAML no branch `main`.

O ArgoCD monitora mudanças de **conteúdo** no path `k8s/` do branch `main`. Para que ele detecte a nova versão:

1. O arquivo de manifesto (`k8s/kube-news-green.yaml` ou `k8s/kube-news-blue.yaml`) deve ser **editado** para referenciar a nova tag como imagem (`image: updateinformatica/claude-devops:v2.0.0`)
2. Essa edição deve ser **commitada e pushed** para o branch `main`
3. Somente então o ArgoCD detectará a divergência (OutOfSync) e aplicará automaticamente (automated sync está habilitado com `selfHeal: true` e `prune: true`)

### Fluxo atual configurado no ArgoCD
```
targetRevision: main   <-- rastreia o branch, não tags
automated:
  prune: true
  selfHeal: true
```

O ArgoCD **não** está configurado para usar `targetRevision: v2.0.0` (uma tag específica). Se estivesse, precisaria de uma tag para cada deploy.

---

## Problemas Adicionais Encontrados

### 1. argocd-applicationset-controller em CrashLoopBackOff
- **Pod:** `argocd-applicationset-controller-6d9bc95cc7-rgkdp`
- **Status:** `CrashLoopBackOff` (22 restarts em 137 minutos)
- **Erro:** `failed to get restmapping: no matches for kind "ApplicationSet" in version "argoproj.io/v1alpha1"`
- **Causa:** O CRD `applicationsets.argoproj.io` **não está instalado** no cluster. A lista de CRDs confirma sua ausência.
- **Impacto:** O controlador ApplicationSet está inoperante. Porém, como a aplicação `kube-news` é um `Application` simples (não um `ApplicationSet`), isso **não afeta** o funcionamento atual.
- **Ação necessária:** Reinstalar o ArgoCD com os CRDs completos, ou instalar o CRD manualmente.

### 2. Divergência de imagem no manifesto local vs. cluster
- `k8s/kube-news-blue.yaml` local declara `v1.2.6` mas o cluster está rodando `1.0`
- O ArgoCD sincronizou com base no commit `ae0267c5`, que possivelmente tinha `1.0` no blue
- O arquivo local pode ter sido editado manualmente sem ser commitado/pushed

---

## O Que Fazer para Deployar v2.0.0

### Opção A — Blue-Green: promover green para v2.0.0 (recomendado)

1. Editar `k8s/kube-news-green.yaml`:
   ```yaml
   image: updateinformatica/claude-devops:v2.0.0
   ```
2. Commit e push para `main`:
   ```bash
   git add k8s/kube-news-green.yaml
   git commit -m "feat: promove kube-news-green para v2.0.0"
   git push origin main
   ```
3. O ArgoCD detectará OutOfSync e aplicará automaticamente dentro de ~3 minutos (ou imediatamente via self-heal)
4. Validar o green em preview antes de chavear o tráfego

### Opção B — Mudar targetRevision para a tag (não recomendado para fluxo contínuo)

Alterar o Application do ArgoCD para `targetRevision: v2.0.0`. Isso exigiria uma nova tag para cada release e não é compatível com o fluxo Blue-Green atual.

---

## Estado dos Pods ArgoCD

| Pod | Status | Observação |
|---|---|---|
| argocd-application-controller-0 | Running | OK — responsável pelo sync |
| argocd-applicationset-controller | CrashLoopBackOff | CRD ausente — não afeta fluxo atual |
| argocd-dex-server | Running | OK |
| argocd-notifications-controller | Running | OK |
| argocd-redis | Running | OK |
| argocd-repo-server | Running | OK — cache de manifesto funcionando |
| argocd-server | Running | OK |

---

## Conclusão

O ArgoCD está saudável e sincronizado. O problema não é de sincronização — é de **processo GitOps incompleto**: criar uma tag git não dispara um novo deploy. Para deployar v2.0.0, é necessário atualizar o campo `image:` no manifesto YAML correspondente, commitar e fazer push para `main`. O ArgoCD irá detectar e aplicar automaticamente.
