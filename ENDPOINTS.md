# Endpoints da Aplicação

## GET /

**Descrição:** Página inicial — lista todas as notícias cadastradas e renderiza a view HTML
**Parâmetros:** Nenhum
**Retorno:** Página HTML com a lista de postagens
**Códigos HTTP:** 200 (sucesso), 500 (erro interno / banco indisponível)

---

## GET /post

**Descrição:** Exibe o formulário HTML para criação de uma nova notícia
**Parâmetros:** Nenhum
**Retorno:** Página HTML com o formulário em branco
**Códigos HTTP:** 200 (sucesso), 500 (erro interno)

---

## POST /post

**Descrição:** Processa o envio do formulário de criação de notícia. Valida os campos e salva no banco; em caso de sucesso redireciona para `/`; em caso de falha de validação, re-renderiza o formulário com os dados preenchidos e indicação de erro
**Parâmetros (body — form-urlencoded):**

| Campo | Tipo | Regra de validação |
|-------|------|--------------------|
| `title` | string | obrigatório, < 30 caracteres |
| `resumo` | string | obrigatório, < 50 caracteres |
| `description` | string | obrigatório, < 2000 caracteres |

**Retorno:** Redirect para `/` (sucesso) ou página HTML com formulário e erro (validação falhou)
**Códigos HTTP:** 302 (redirect para `/`), 200 (re-renderiza formulário com erro), 500 (erro interno)

---

## POST /api/post

**Descrição:** API REST para inserção em lote de notícias. Recebe um array de artigos e persiste todos no banco. Não realiza validação dos campos
**Parâmetros (body — JSON):**

```json
{
  "artigos": [
    {
      "title": "Título da notícia",
      "resumo": "Resumo curto",
      "description": "Conteúdo completo"
    }
  ]
}
```

**Retorno:** Array JSON com os artigos recebidos
**Códigos HTTP:** 200 (sucesso), 500 (erro interno)

---

## GET /post/:id

**Descrição:** Exibe o detalhe completo de uma notícia pelo seu identificador único
**Parâmetros (path):**

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `id` | integer | ID primário do post no banco |

**Retorno:** Página HTML com o conteúdo completo da notícia
**Códigos HTTP:** 200 (sucesso), 500 (erro interno ou ID inexistente)

---

## GET /metrics

**Descrição:** Expõe métricas no formato Prometheus para scraping. Inclui o contador customizado `http_requests_total` e histogramas por rota, método e status code gerados pelo `express-prom-bundle`
**Parâmetros:** Nenhum
**Retorno:** Texto no formato Prometheus exposition format
**Códigos HTTP:** 200 (sucesso)

---

## GET /health

**Descrição:** Liveness probe — indica se a aplicação está viva. Retorna o hostname da máquina/pod onde está rodando
**Parâmetros:** Nenhum
**Retorno:** JSON com estado e hostname — `{ "state": "up", "machine": "<hostname>" }`
**Códigos HTTP:** 200 (aplicação saudável), 500 (quando `/unhealth` foi acionado)

---

## GET /ready

**Descrição:** Readiness probe — indica se a aplicação está pronta para receber tráfego. Usado pelo Kubernetes para controlar se o pod entra no balanceamento de carga
**Parâmetros:** Nenhum
**Retorno:** Texto `Ok` (pronto) ou vazio (não pronto)
**Códigos HTTP:** 200 (pronto), 500 (em período de "unready" após `PUT /unreadyfor/:seconds`)

---

## PUT /unhealth

**Descrição:** Endpoint de caos — ativa uma flag de processo que faz todos os requests subsequentes retornarem 500, simulando uma falha total da aplicação. O estado só é revertido com o restart do processo/pod
**Parâmetros:** Nenhum
**Retorno:** Texto `OK`
**Códigos HTTP:** 200 (flag ativada com sucesso)

---

## PUT /unreadyfor/:seconds

**Descrição:** Endpoint de caos — faz o `/ready` retornar 500 por N segundos, simulando indisponibilidade temporária. Útil para testar comportamento de rolling deployment e readiness gates no Kubernetes
**Parâmetros (path):**

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `seconds` | integer | Duração em segundos que o `/ready` ficará retornando 500 |

**Retorno:** Texto `OK`
**Códigos HTTP:** 200 (temporizador configurado com sucesso)
