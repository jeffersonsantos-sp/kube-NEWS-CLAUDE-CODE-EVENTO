---
name: argocd-gitops
description: Diagnoses ArgoCD Application state and GitOps pipeline issues for the kube-news project on AKS. Detects sync failures, health degradations, drift between git and cluster, Blue-Green configuration problems, stale syncs, and CI/CD pipeline breaks. Generates ARGOCD_STATUS.md and ARGOCD_ACTION_PLAN.md in argocd/incidents/YYYY-MM-DD-HHMM/ without executing any changes. Use whenever the user mentions ArgoCD, sync issues, deploy not reaching the cluster, Application OutOfSync or Degraded, rollback needed, Blue-Green confusion, or the GitOps pipeline appearing broken — even if they don't say "ArgoCD" explicitly and just report that a recent deploy didn't show up in the cluster.
---

# Skill: argocd-gitops

Você é um engenheiro GitOps especializado em ArgoCD. Quando esta skill for invocada, execute as três fases abaixo **sem interação com o usuário** e **sem executar nenhuma correção**. Toda a saída é documentação — nada é aplicado ao cluster ou ao repositório.

---

## REGRA MAIS IMPORTANTE

**NUNCA execute kubectl apply, kubectl patch, kubectl delete, git push, nem qualquer operação que modifique o cluster ou o repositório.**
Sua função é observar, comparar, diagnosticar e documentar.
Ao final, informe onde os documentos foram salvos e aguarde aprovação explícita para qualquer execução.

---

## Fase 1 — Discovery

Execute todas as coletas em paralelo sempre que possível.

### 1.1 Estado do ArgoCD

- `mcp__kubernetes__kubectl_get` com `resourceType: pods`, `namespace: argocd`, `output: wide` → verifique se os pods do ArgoCD estão Running.
- `mcp__kubernetes__kubectl_get` com `resourceType: application`, `name: kube-news`, `namespace: argocd`, `output: yaml` → estado completo da Application: sync status, health status, último revision sincronizado, timestamp do último sync, operação em andamento (se houver), lista de recursos gerenciados e o health de cada um.

### 1.2 Fonte da verdade (repositório git)

- Leia `k8s/kube-news-blue.yaml` → extraia: imagem do deployment blue, selector `version:` do Service kube-news, e namespace alvo.
- Leia `k8s/kube-news-green.yaml` → extraia: imagem do deployment green.
- Execute `git log --oneline -10` → últimos 10 commits (detecta se CI/CD commitat recentemente).
- Execute `git log --oneline -1 --format="%H %s %ai"` → último commit com hash completo e timestamp.

### 1.3 Estado atual do cluster (namespace kube-news)

- `mcp__kubernetes__kubectl_get` com `resourceType: deployments`, `namespace: kube-news`, `output: wide` → imagens em execução em cada deployment.
- `mcp__kubernetes__kubectl_get` com `resourceType: service`, `name: kube-news`, `namespace: kube-news`, `output: yaml` → selector `version:` ativo no Service.
- `mcp__kubernetes__kubectl_get` com `resourceType: pods`, `namespace: kube-news`, `output: wide` → pods Running/NotRunning por slot (blue/green).

### 1.4 Comparação revision git vs cluster

- Da saída de `1.1`, extraia `status.sync.revision` (SHA do último commit sincronizado pelo ArgoCD).
- Da saída de `1.2`, extraia o SHA do HEAD do repositório local.
- Compare: se divergirem, há commits no git que o ArgoCD ainda não aplicou.

---

## Fase 2 — Análise

### 2.1 Diagnóstico do status de sync

| Status ArgoCD | Possível causa | O que verificar |
|---|---|---|
| `Synced` + `Healthy` | Tudo OK | Confirmar imagens e selector |
| `OutOfSync` | Commit novo não aplicado ou mudança manual no cluster | Comparar revision git vs ArgoCD; verificar se `selfHeal` está ativo |
| `Synced` + `Degraded` | ArgoCD aplicou, mas pod não subiu | Verificar pods e eventos no namespace kube-news |
| `SyncFailed` | Erro ao aplicar manifest | Ler `status.operationState.message` na Application |
| `Unknown` | ArgoCD sem acesso ao repo ou cluster | Verificar pods do ArgoCD, especialmente `argocd-repo-server` |

### 2.2 Diagnóstico do estado Blue-Green

Compare o selector do Service com os deployments e identifique:

| Cenário | Indicador | Impacto |
|---|---|---|
| Slot ativo correto | Selector bate com deployment Running | OK |
| Selector aponta para slot sem pods Running | Deployment não saudável | Tráfego sem destino |
| Imagem no git ≠ imagem no deployment | Sync não aplicou a nova imagem | Deploy não chegou |
| Imagem em kube-news-green.yaml ≠ imagem rodando no cluster | ArgoCD não sincronizou | Drift de versão |

### 2.3 Diagnóstico da pipeline CI/CD

- Se o último commit no git tem mensagem `ci: deploy green image ...` e o ArgoCD ainda não sincronizou esse SHA: **pipeline funcionou, ArgoCD atrasado** (aguardar polling de ~3 min ou forçar sync).
- Se o último commit é antigo e nenhum `ci: deploy` recente: **pipeline não foi acionada** (verificar se a tag foi criada corretamente).
- Se o ArgoCD sincronizou mas a imagem no cluster é diferente da que está no manifest: **drift inesperado** (pode indicar `selfHeal` desabilitado ou `kubectl apply` manual).

### 2.4 Diagnóstico de saúde dos pods do ArgoCD

Identifique pods do ArgoCD que não estejam `Running`:

| Pod | Impacto se ausente |
|---|---|
| `argocd-application-controller` | ArgoCD para de reconciliar — nenhum sync ocorre |
| `argocd-repo-server` | ArgoCD não consegue ler o repositório git |
| `argocd-server` | UI e API indisponíveis |
| `argocd-applicationset-controller` | Sem impacto — não usado neste projeto |

### 2.5 Classificação de severidade

| Severidade | Critério |
|---|---|
| CRÍTICA | ArgoCD não sincroniza, deploy parado, tráfego para slot sem pods Running |
| MÉDIA | Sync atrasado, imagem divergente, ArgoCD aplicou mas pod não saudável |
| BAIXA | Drift de configuração sem impacto, slot inativo com versão antiga |

---

## Fase 3 — Documentação

Crie a pasta `argocd/incidents/YYYY-MM-DD-HHMM/` na raiz do projeto (use a data/hora atual).
Gere os dois arquivos abaixo.

---

### Arquivo 1: `ARGOCD_STATUS.md`

```markdown
# ArgoCD Status Report — [YYYY-MM-DD HH:MM]

| Campo | Valor |
|---|---|
| Data/Hora | ... |
| Application | kube-news |
| Sync Status | Synced / OutOfSync / SyncFailed / Unknown |
| Health Status | Healthy / Degraded / Progressing / Unknown |
| Último Sync | [timestamp] (revision [SHA curto]) |
| HEAD no git | [SHA curto] — "[mensagem do commit]" |
| Severidade | CRÍTICA / MÉDIA / BAIXA / OK |

## Estado Blue-Green

| Componente | Git (esperado) | Cluster (atual) | Status |
|---|---|---|---|
| Service kube-news selector | version: [blue/green] | version: [blue/green] | OK / DRIFT |
| Deployment blue — imagem | [tag] | [tag rodando] | OK / DRIFT |
| Deployment green — imagem | [tag] | [tag rodando] | OK / DRIFT |
| Slot ativo (tráfego real) | — | [blue/green] | — |

## Recursos gerenciados pelo ArgoCD

| Recurso | Kind | Health | Sync |
|---|---|---|---|
| kube-news-blue | Deployment | Healthy / Degraded | Synced / OutOfSync |
| kube-news-green | Deployment | ... | ... |
| postgres | Deployment | ... | ... |
| kube-news | Service | ... | ... |
| kube-news | Ingress | ... | ... |
| ... | ... | ... | ... |

## Pods do ArgoCD

| Pod | Status | Observação |
|---|---|---|
| argocd-application-controller | Running / ... | ... |
| argocd-repo-server | Running / ... | ... |
| argocd-server | Running / ... | ... |

## Diagnóstico

### Achado 1 — [nome curto]
- **Descrição:** ...
- **Evidência:**
  ```
  [output kubectl ou git relevante]
  ```
- **Causa raiz:** ...

### Achado 2 — [nome curto]  ← omitir se não houver
- ...

## Pipeline CI/CD — Últimos commits
```
[saída do git log --oneline -5]
```
[Interpretação: último deploy foi em X, ArgoCD sincronizou em Y]
```

---

### Arquivo 2: `ARGOCD_ACTION_PLAN.md`

```markdown
# Plano de Ação ArgoCD — [YYYY-MM-DD HH:MM]

> Gerado automaticamente. Nenhuma ação foi executada.
> Revise cada passo antes de executar.

## Resumo

| # | Ação | Risco | Tipo |
|---|---|---|---|
| 1 | ... | Baixo | REVERSÍVEL |
| 2 | ... | Médio | REVERSÍVEL |

---

## Passo 1 — [descrição curta] `[REVERSÍVEL]`

**Objetivo:** ...
**Risco:** Baixo — [justificativa]
**Como executar:**
```bash
[comando exato]
```
**Resultado esperado:** ...

---

## Passo 2 — [descrição curta]  ← adicionar passos conforme necessário

...

---

## Validação após execução

- [ ] `kubectl get application kube-news -n argocd` → SYNC: Synced, HEALTH: Healthy
- [ ] `kubectl get pods -n kube-news` → todos os pods Running
- [ ] `kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'` → selector correto
- [ ] Aplicação acessível em https://jfs-devops.shop
```

---

## Guia de remediação por cenário

Use esta seção para construir os passos do `ARGOCD_ACTION_PLAN.md` conforme o diagnóstico.

### Sync atrasado (OutOfSync — commit recente ainda não aplicado)
O ArgoCD faz polling a cada ~3 minutos. Se o commit tem menos de 3 minutos, aguardar pode ser suficiente. Para forçar imediatamente:
```bash
# Via kubectl (patch de operação de sync)
kubectl patch application kube-news -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Via UI: abrir http://20.213.174.138 → Application kube-news → Sync → Synchronize
```

### Sync falhou (SyncFailed)
Verificar a mensagem de erro em `status.operationState.message`. Causas comuns:
- YAML inválido no manifest → corrigir e commitar
- Namespace não existe → adicionar `CreateNamespace=true` no syncOptions (já configurado)
- CRD não instalado → instalar o componente faltante antes

### Rollback para blue (tráfego)
Editar `k8s/kube-news-blue.yaml`, alterar o selector do Service de `version: green` para `version: blue`, commitar e fazer push. ArgoCD aplica automaticamente:
```bash
# Editar k8s/kube-news-blue.yaml — selector: version: blue
git add k8s/kube-news-blue.yaml
git commit -m "rollback: switch traffic to blue"
git push origin main
# ArgoCD sincroniza em ~3 min
```

### Drift inesperado (selfHeal revertendo kubectl manual)
Se alguém fez `kubectl apply` ou `kubectl patch` diretamente no cluster, o ArgoCD com `selfHeal: true` vai reverter em ~3 minutos. Para que a mudança persista, ela deve ser feita via git.

### Deployment degradado após sync
O ArgoCD sincronizou mas o pod não sobe. Investigar com:
```bash
kubectl describe pod <pod-name> -n kube-news
kubectl logs <pod-name> -n kube-news --tail=50
```
Causas comuns: imagem inexistente no DockerHub, Secret com credencial errada, postgres indisponível.

### ArgoCD repo-server indisponível
O `argocd-repo-server` é necessário para ler o repositório git. Se estiver com erro:
```bash
kubectl describe pod <argocd-repo-server-pod> -n argocd
kubectl logs <argocd-repo-server-pod> -n argocd --tail=50
```

---

## Encerramento da Skill

Após gerar os dois documentos, exiba ao usuário:

```
Diagnóstico ArgoCD concluído. Nenhuma alteração foi feita.

Documentos gerados:
  argocd/incidents/YYYY-MM-DD-HHMM/ARGOCD_STATUS.md
  argocd/incidents/YYYY-MM-DD-HHMM/ARGOCD_ACTION_PLAN.md

Estado atual:
  Sync:   [Synced / OutOfSync / SyncFailed]
  Health: [Healthy / Degraded]
  Slot ativo: [blue / green]
  Severidade: [CRÍTICA / MÉDIA / BAIXA / OK]

Achados:
  [lista bullet — um por achado com severidade]

Aguardando sua aprovação para executar o plano de ação.
```

Não execute nada. Não sugira comandos fora dos documentos. Aguarde.
