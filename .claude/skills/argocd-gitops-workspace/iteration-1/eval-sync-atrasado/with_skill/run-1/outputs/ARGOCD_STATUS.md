# ArgoCD Status Report — 2026-06-03 21:05

| Campo | Valor |
|---|---|
| Data/Hora | 2026-06-03 21:05 |
| Application | kube-news |
| Sync Status | Unknown (cluster inacessível — ver Achado 1) |
| Health Status | Unknown (cluster inacessível) |
| Último Sync | Indisponível — kubectl falhou com erro DNS |
| HEAD no git | 5a1af2b — "Atualização da imagem blue v1.2.6" (2026-06-03 17:52 -0300) |
| Severidade | CRÍTICA |

## Estado Blue-Green

| Componente | Git (esperado) | Cluster (atual) | Status |
|---|---|---|---|
| Service kube-news selector | version: blue | Indisponível (cluster inacessível) | INDETERMINADO |
| Deployment blue — imagem | updateinformatica/claude-devops:v1.2.6 | Indisponível | INDETERMINADO |
| Deployment green — imagem | updateinformatica/claude-devops:v1.2.5 | Indisponível | INDETERMINADO |
| Slot ativo (tráfego real) | blue (pelo manifest git) | Indisponível | — |

> NOTA: A tag v2.0.0 reportada pelo usuário NÃO aparece nos tags locais nem existe commit `ci: deploy green image v2.0.0` no histórico. Ver Achado 2 e Achado 3.

## Recursos gerenciados pelo ArgoCD

O ArgoCD gerencia os seguintes recursos via `path: k8s` no branch `main`:

| Recurso | Kind | Health | Sync |
|---|---|---|---|
| kube-news-blue | Deployment | Indisponível | Indisponível |
| kube-news-green | Deployment | Indisponível | Indisponível |
| postgres | Deployment | Indisponível | Indisponível |
| kube-news | Service (ClusterIP) | Indisponível | Indisponível |
| kube-news-preview | Service (ClusterIP) | Indisponível | Indisponível |
| postgres | Service (ClusterIP) | Indisponível | Indisponível |
| kube-news | Ingress | Indisponível | Indisponível |
| letsencrypt-staging | ClusterIssuer | Indisponível | Indisponível |
| letsencrypt-prod | ClusterIssuer | Indisponível | Indisponível |
| kube-news-secret | Secret | Indisponível | Indisponível |
| kube-news-config | ConfigMap | Indisponível | Indisponível |
| postgres-pvc | PersistentVolumeClaim | Indisponível | Indisponível |

> O cluster AKS (`aks-kube-news-ka8p6h1z.hcp.australiaeast.azmk8s.io`) está inacessível. Os estados acima não puderam ser coletados ao vivo.

## Pods do ArgoCD

| Pod | Status | Observação |
|---|---|---|
| argocd-application-controller | Indisponível | Cluster inacessível — não foi possível verificar |
| argocd-repo-server | Indisponível | Cluster inacessível — não foi possível verificar |
| argocd-server | Indisponível | Cluster inacessível — UI em http://20.213.174.138 não verificada |
| argocd-dex-server | Indisponível | — |
| argocd-redis | Indisponível | — |

## Diagnóstico

### Achado 1 — Cluster AKS inacessível (CRÍTICO)

- **Descrição:** Nenhum comando `kubectl` conseguiu conectar ao cluster AKS. O DNS não resolve o hostname do API server do AKS.
- **Evidência:**
  ```
  Unable to connect to the server: dial tcp: lookup aks-kube-news-ka8p6h1z.hcp.australiaeast.azmk8s.io
  on 192.168.65.7:53: no such host
  ```
- **Causa raiz:** O cluster AKS está parado/desalocado (comum em ambientes de laboratório para reduzir custo), ou o KUBECONFIG está apontando para um endpoint desatualizado. Isso impede tanto o `kubectl` direto quanto o ArgoCD de sincronizar — o `argocd-application-controller` não consegue se comunicar com o API server.

---

### Achado 2 — Tag v2.0.0 não encontrada no repositório local (CRÍTICO)

- **Descrição:** O usuário relatou ter executado `git tag v2.0.0` e `git push`, mas a tag v2.0.0 não aparece nos tags do repositório local e nenhum commit com mensagem `ci: deploy green image v2.0.0` existe no histórico git.
- **Evidência:**
  ```
  Tags presentes: v1.2.6, v1.2.5, v1.0.2, v1.2.4, v1.2.3
  Último commit: 5a1af2b — "Atualização da imagem blue v1.2.6" (2026-06-03 17:52:35)
  Nenhum commit "ci: deploy green image v2.0.0" encontrado
  ```
- **Causa raiz:** Possibilidades: (a) A tag foi criada localmente mas `git push origin v2.0.0` falhou silenciosamente; (b) A tag foi criada com outro nome; (c) O push foi feito para um remote diferente. Sem a tag no GitHub, o workflow CI (`on: push: tags: v*.*.*`) nunca foi disparado.

---

### Achado 3 — Pipeline CI/CD não executou para v2.0.0 (CRÍTICO)

- **Descrição:** O CD workflow atualiza `k8s/kube-news-green.yaml` com a nova tag e commita com a mensagem `ci: deploy green image <TAG>`. Como esse commit não existe no histórico, o CD não foi executado. Consequentemente, o manifest `kube-news-green.yaml` ainda contém `image: updateinformatica/claude-devops:v1.2.5` — a imagem v2.0.0 nunca foi escrita nos manifests que o ArgoCD monitora.
- **Evidência:**
  ```
  k8s/kube-news-green.yaml — linha 20:
    image: updateinformatica/claude-devops:v1.2.5

  git log --oneline -5:
  5a1af2b Atualização da imagem blue v1.2.6
  63d3878 Atualização da imagem blue v1.2.5
  8b7d003 Atualização da imagem v1.2.5
  3245b8c docs: atualiza CLAUDE.md com seção ArgoCD e GitOps
  6b5d6c1 docs: adiciona ARGOCD.md com documentação completa do CI/CD GitOps
  ```
- **Causa raiz:** A cadeia GitOps foi quebrada no primeiro elo: sem a tag no GitHub, o CI não buildou a imagem, o CD não atualizou o manifest, e o ArgoCD não teve nada novo para sincronizar.

---

### Achado 4 — Selector do Service aponta para blue com imagem v1.2.6 (BAIXO)

- **Descrição:** O Service `kube-news` tem `selector: version: blue` e o Deployment `kube-news-blue` usa `image: updateinformatica/claude-devops:v1.2.6`. O slot green está em standby com v1.2.5. Esta é a configuração esperada para o estado atual (sem novo deploy).
- **Evidência:**
  ```
  k8s/kube-news-blue.yaml — Service kube-news selector:
    app: kube-news
    version: blue

  k8s/kube-news-blue.yaml — Deployment kube-news-blue:
    image: updateinformatica/claude-devops:v1.2.6

  k8s/kube-news-green.yaml — Deployment kube-news-green:
    image: updateinformatica/claude-devops:v1.2.5
  ```
- **Causa raiz:** Não é um problema — é o estado normal do Blue-Green quando o último deploy bem-sucedido foi v1.2.6 para o slot blue.

## Pipeline CI/CD — Últimos commits

```
5a1af2b Atualização da imagem blue v1.2.6
63d3878 Atualização da imagem blue v1.2.5
8b7d003 Atualização da imagem v1.2.5
3245b8c docs: atualiza CLAUDE.md com seção ArgoCD e GitOps
6b5d6c1 docs: adiciona ARGOCD.md com documentação completa do CI/CD GitOps
```

**Interpretação:** O último deploy automático (CI/CD) foi para v1.2.5/v1.2.6. Não existe nenhum commit `ci: deploy green image v2.0.0` — a pipeline não foi acionada para esta versão. O ArgoCD está sincronizando o estado atual do git (sem v2.0.0), portanto o comportamento observado pelo usuário ("imagem não apareceu") é esperado dado que a pipeline não executou.
