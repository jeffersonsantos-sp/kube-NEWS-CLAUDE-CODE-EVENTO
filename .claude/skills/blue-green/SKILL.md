---
name: blue-green
description: Executes Blue-Green deployment operations for the kube-news project on AKS via GitOps. Handles traffic switching (blue↔green), rollback, manual green deploy with a specific image tag, and blue baseline update. All changes go through git commit + push — ArgoCD applies them to the cluster automatically. Use whenever the user wants to switch traffic slots, rollback a deploy, promote green to production, deploy a specific image manually, check which slot is active, or do anything related to Blue-Green — even if they just say "rollback", "subir versão X", "qual slot está ativo", or "promover green".
---

# Skill: blue-green

Você é o operador de deploys Blue-Green do projeto kube-news. Todas as operações são feitas via **git commit + push** — o ArgoCD detecta a mudança e aplica no cluster automaticamente em ~3 minutos. Nunca use `kubectl apply`, `kubectl patch` ou qualquer comando que modifique o cluster diretamente, pois o `selfHeal` do ArgoCD reverteria a mudança.

---

## Passo 1 — Ler o estado atual

Antes de qualquer operação, leia o estado atual em paralelo:

- `k8s/kube-news-blue.yaml` — extraia o selector `version:` do Service `kube-news` (4 espaços de indentação, na seção `spec.selector`). Esse valor (`blue` ou `green`) determina qual slot está recebendo tráfego.
- `k8s/kube-news-green.yaml` — extraia a imagem do deployment green (`image:` field).
- Execute `git log --oneline -5` — veja os últimos commits para entender o histórico de deploys.
- (Opcional, se o cluster estiver acessível) `mcp__kubernetes__kubectl_get` com `resourceType: deployments`, `namespace: kube-news`, `output: wide` — confirme as imagens rodando no cluster.

Após a leitura, mostre um resumo do estado atual antes de executar qualquer operação:

```
Estado atual:
  Slot ativo:       [blue / green]
  Imagem blue:      updateinformatica/claude-devops:[tag]
  Imagem green:     updateinformatica/claude-devops:[tag]
  Último commit:    [hash] [mensagem]
```

---

## Passo 2 — Identificar a operação solicitada

Com base na intenção do usuário, execute a operação correspondente:

| Intenção do usuário | Operação |
|---|---|
| "rollback", "voltar para blue", "reverter" | → [Rollback](#rollback) |
| "switch para green", "promover green", "ativar green" | → [Switch para green](#switch-para-green) |
| "deploy [tag]", "subir versão X", "atualizar para X" | → [Deploy manual no green](#deploy-manual-no-green) |
| "atualizar blue", "sincronizar blue com green" | → [Atualizar baseline blue](#atualizar-baseline-blue) |
| "status", "qual slot está ativo", "qual versão está rodando" | → apenas reportar o estado (Passo 1), sem executar operação |

Se a intenção não estiver clara, pergunte ao usuário qual operação deseja antes de prosseguir.

---

## Operações

### Rollback

Redireciona o tráfego de green para blue. Use quando o deploy em green apresentar problemas.

**O que faz:** altera o selector do Service `kube-news` de `version: green` para `version: blue` em `k8s/kube-news-blue.yaml`.

**Antes de executar:** confirme que o deployment blue tem pods Running (via cluster ou manifests).

**Implementação:**

```bash
# 1. Verifica que o selector atual é green (rollback faz sentido)
grep "^    version:" k8s/kube-news-blue.yaml

# 2. Altera apenas o selector do Service (4 espaços — não altera labels do Deployment com 6 espaços)
sed -i 's/^    version: green$/    version: blue/' k8s/kube-news-blue.yaml

# 3. Confirma a mudança antes de commitar
grep "^    version:" k8s/kube-news-blue.yaml

# 4. Commita e faz push
git add k8s/kube-news-blue.yaml
git commit -m "rollback: switch traffic to blue"
git push origin main
```

**Resultado:** ArgoCD aplica em ~3 min. Todo o tráfego vai para o slot blue.

---

### Switch para green

Redireciona o tráfego de blue para green. Use após verificar que o green está saudável.

**O que faz:** altera o selector do Service `kube-news` de `version: blue` para `version: green` em `k8s/kube-news-blue.yaml`.

**Implementação:**

```bash
sed -i 's/^    version: blue$/    version: green/' k8s/kube-news-blue.yaml
git add k8s/kube-news-blue.yaml
git commit -m "deploy: switch traffic to green"
git push origin main
```

**Resultado:** ArgoCD aplica em ~3 min. Todo o tráfego vai para o slot green.

---

### Deploy manual no green

Atualiza a imagem do deployment green e direciona o tráfego para ele. Use quando quiser deploiar uma tag específica sem passar pelo pipeline CI/CD.

**O que faz:**
1. Atualiza `image:` em `k8s/kube-news-green.yaml` com a nova tag
2. Atualiza o selector do Service para `version: green` em `k8s/kube-news-blue.yaml`

**Implementação** (substitua `NEW_TAG` pela tag desejada):

```bash
# 1. Atualiza a imagem no deployment green
sed -i "s|image: updateinformatica/claude-devops:.*|image: updateinformatica/claude-devops:NEW_TAG|" k8s/kube-news-green.yaml

# 2. Garante que o selector aponta para green
sed -i 's/^    version: blue$/    version: green/' k8s/kube-news-blue.yaml

# 3. Confirma as mudanças
grep "image:" k8s/kube-news-green.yaml
grep "^    version:" k8s/kube-news-blue.yaml

# 4. Commita e faz push
git add k8s/kube-news-green.yaml k8s/kube-news-blue.yaml
git commit -m "deploy: green image NEW_TAG"
git push origin main
```

**Resultado:** ArgoCD deploya a nova imagem no green e direciona o tráfego para ele em ~3 min.

---

### Atualizar baseline blue

Atualiza a imagem do deployment blue para igualar a do green. Use após confirmar que o green está estável e querer definir um novo ponto de rollback.

**O que faz:** copia a tag da imagem de `k8s/kube-news-green.yaml` para `k8s/kube-news-blue.yaml`. O selector do Service não é alterado.

**Implementação:**

```bash
# 1. Extrai a tag atual do green
GREEN_TAG=$(grep "image: updateinformatica/claude-devops:" k8s/kube-news-green.yaml | sed 's/.*://')

# 2. Atualiza a imagem do blue com a mesma tag
sed -i "s|image: updateinformatica/claude-devops:.*|image: updateinformatica/claude-devops:${GREEN_TAG}|" k8s/kube-news-blue.yaml

# 3. Confirma
grep "image: updateinformatica/claude-devops:" k8s/kube-news-blue.yaml

# 4. Commita e faz push
git add k8s/kube-news-blue.yaml
git commit -m "chore: update blue baseline to ${GREEN_TAG}"
git push origin main
```

**Resultado:** Blue passa a ter a mesma imagem que green. O próximo rollback vai para essa versão.

---

## Passo 3 — Confirmar a execução

Após executar a operação, informe ao usuário:

```
Operação concluída: [nome da operação]

Mudanças aplicadas:
  [arquivo alterado] — [o que mudou]

Commit: [hash] "[mensagem do commit]"

O ArgoCD vai sincronizar em ~3 minutos.
Para acompanhar: http://20.213.174.138 → Application kube-news

Estado após a operação:
  Slot ativo:   [blue / green]
  Imagem blue:  updateinformatica/claude-devops:[tag]
  Imagem green: updateinformatica/claude-devops:[tag]
```

---

## Referência rápida

| Arquivo | O que controla |
|---|---|
| `k8s/kube-news-blue.yaml` (selector `version:` com 4 espaços) | Qual slot recebe tráfego de produção |
| `k8s/kube-news-green.yaml` (campo `image:`) | Imagem rodando no slot green |
| `k8s/kube-news-blue.yaml` (campo `image:` no Deployment blue) | Imagem rodando no slot blue (baseline de rollback) |

> **Atenção ao sed:** o selector do Service usa `    version:` (4 espaços). Os labels do Deployment usam `      version:` (6 espaços). O padrão `^    version:` com âncora de início de linha garante que apenas o selector seja alterado.
