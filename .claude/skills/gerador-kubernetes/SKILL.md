---
name: gerador-kubernetes
description: Gera manifestos Kubernetes em k8s/ a partir do docker-compose.yml do projeto, aplicando Blue-Green por padrão, separação de Secret/ConfigMap, probes, PVC para serviços stateful e boas práticas consolidadas. Use quando o usuário quiser criar ou gerar manifestos Kubernetes para o projeto.
---

## O que esta skill faz

Lê o `docker-compose.yml` do projeto e gera os manifestos Kubernetes em `k8s/`, sempre em dois arquivos:

- `k8s/<nome>-blue.yaml` — infraestrutura completa + deployment da versão ativa
- `k8s/<nome>-green.yaml` — deployment da nova versão + service de preview

Aplica todas as regras abaixo sem pedir confirmação. Ao final, exibe um resumo das decisões tomadas.

---

## Regras obrigatórias

### 1. Distinção app vs infraestrutura

Determina quem recebe Blue-Green e quem recebe PVC:

- Serviço com `build:` no docker-compose → **app**
- Serviço com apenas `image:` de nome conhecido → **infraestrutura**
- Serviço com `image:` desconhecida sem `build:` → tratar como **app** (fallback conservador)

**Imagens de infraestrutura conhecidas:**
`postgres`, `mysql`, `mariadb`, `redis`, `rabbitmq`, `mongo`, `elasticsearch`, `kafka`, `zookeeper`, `nginx`

### 2. Blue-Green obrigatório para toda app

Toda app recebe dois Deployments e dois Services:

- `<nome>-blue` — versão ativa em produção (`replicas: 2`)
- `<nome>-green` — nova versão em standby (`replicas: 2` no green.yaml; pronto para subir)
- Service de produção (`LoadBalancer`) com `selector: version: blue`
- Service de preview (`ClusterIP`) com `selector: version: green`

**Labels obrigatórias em todo pod Blue-Green:**
```yaml
labels:
  app: <nome>
  version: blue   # ou green
```

Serviços de infraestrutura **não** recebem Blue-Green.

### 3. Separação Secret vs ConfigMap

- **Secret** (`stringData`): senhas, tokens, chaves — qualquer variável de ambiente que contenha `PASSWORD`, `SECRET`, `KEY`, `TOKEN` no nome
- **ConfigMap**: host, porta, nome do banco, flags de configuração — tudo que não é sensível

Nunca colocar credencial em ConfigMap.

### 4. Tag de imagem

- **Proibido** usar `latest`. Se o docker-compose usar `latest` ou não especificar tag, manter a imagem mas alertar no resumo final.
- **Prefira tags explícitas** e imagens Alpine quando disponíveis.

### 5. PVC obrigatório para serviços stateful

Todo serviço de infraestrutura com volume no docker-compose recebe um `PersistentVolumeClaim` de **5Gi** com `accessModes: ReadWriteOnce`.

**Regra específica para PostgreSQL:**
Sempre adicionar a variável de ambiente abaixo para evitar falha de inicialização causada pelo diretório `lost+found` que o filesystem ext4 cria na raiz do PVC:

```yaml
- name: PGDATA
  value: /var/lib/postgresql/data/pgdata
```

### 6. Probes obrigatórias em todo Deployment

**Apps (httpGet):**
```yaml
readinessProbe:
  httpGet:
    path: /
    port: <porta detectada do docker-compose>
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
livenessProbe:
  httpGet:
    path: /
    port: <porta detectada do docker-compose>
  initialDelaySeconds: 30
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 3
```

**PostgreSQL (exec):**
```yaml
readinessProbe:
  exec:
    command: ["pg_isready", "-U", "<usuario>", "-d", "<banco>"]
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5
livenessProbe:
  exec:
    command: ["pg_isready", "-U", "<usuario>", "-d", "<banco>"]
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5
```

**Redis (exec):**
```yaml
readinessProbe:
  exec:
    command: ["redis-cli", "ping"]
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 5
livenessProbe:
  exec:
    command: ["redis-cli", "ping"]
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 5
```

### 7. Resource limits — sempre gerados comentados

Gerar o bloco `resources` comentado em todo Deployment, com valores de referência por tipo. O usuário deve ajustar com base em métricas reais antes de produção.

**Apps Node.js:**
```yaml
# resources:
#   requests:
#     memory: "128Mi"
#     cpu: "100m"
#   limits:
#     memory: "256Mi"
#     cpu: "500m"
```

**PostgreSQL:**
```yaml
# resources:
#   requests:
#     memory: "256Mi"
#     cpu: "250m"
#   limits:
#     memory: "512Mi"
#     cpu: "1000m"
```

**Redis:**
```yaml
# resources:
#   requests:
#     memory: "64Mi"
#     cpu: "50m"
#   limits:
#     memory: "128Mi"
#     cpu: "200m"
```

### 8. Tipos de Service

- App principal → `LoadBalancer`, porta `80` → porta da app
- Preview (green) → `ClusterIP`, porta da app → porta da app
- Infraestrutura (postgres, redis, etc.) → `ClusterIP`, porta padrão do serviço

### 9. Ordem hierárquica no blue.yaml

```
1. Namespace
2. Secret
3. ConfigMap
4. PersistentVolumeClaim (um por serviço stateful)
5. Deployment — infraestrutura (postgres, redis, etc.)
6. Service — infraestrutura (ClusterIP)
7. Deployment — app blue
8. Service — produção (LoadBalancer, selector: blue)
```

---

## Processo de execução

1. **Leia o docker-compose.yml** na raiz do projeto
2. **Classifique cada serviço**: app ou infraestrutura (regra 1)
3. **Extraia as variáveis de ambiente**: separe sensíveis (Secret) das demais (ConfigMap)
4. **Detecte a porta da aplicação** a partir de `ports:` do serviço app
5. **Detecte o nome do projeto**: use o nome do diretório raiz em kebab-case
6. **Gere `k8s/<nome>-blue.yaml`** com a ordem hierárquica (regra 9)
7. **Gere `k8s/<nome>-green.yaml`** com Deployment green + Service preview
8. **Exiba o resumo final**

---

## Resumo final (sempre exibir)

```
## Manifestos gerados

| Regra | Situação | Ação |
|---|---|---|
| Serviços detectados | [lista de apps e infra] | [classificação aplicada] |
| Blue-Green | [apps que receberam] | gerado em blue.yaml e green.yaml |
| Secret | [variáveis sensíveis] | [nomes das keys] |
| ConfigMap | [variáveis não-sensíveis] | [nomes das keys] |
| PVC | [serviços stateful] | [tamanho gerado] |
| PGDATA | [presente / não aplicável] | [ok / adicionado] |
| Probes | [tipo por serviço] | [httpGet / exec] |
| Resource limits | sempre comentados | ajustar antes de produção |
| Tags de imagem | [tags detectadas] | [ok / alerta se latest] |
```

Após o resumo, exibir os comandos de uso:

```bash
# Deploy inicial
kubectl apply -f k8s/<nome>-blue.yaml

# Nova versão (edite a image no green.yaml antes)
kubectl apply -f k8s/<nome>-green.yaml

# Validar green via preview
kubectl port-forward svc/<nome>-preview 8080:8080 -n <namespace>

# Ativar green em produção (edite version: blue → green no blue.yaml)
kubectl apply -f k8s/<nome>-blue.yaml

# Rollback (edite version: green → blue no blue.yaml)
kubectl apply -f k8s/<nome>-blue.yaml
```
