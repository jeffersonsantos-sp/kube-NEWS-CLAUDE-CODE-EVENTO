# Criar Dockerfile

Essa aplicação precisa ser executada utilizando o container Docker então o próximo passo é fazer a criação do Dockerfile e do Docker Compose. 
- Analise o projeto para entender as tecnologias e dependências
- O Dockerfile deve seguir as boas práticas
- O Docker compose será utilizado para desenvolvimento

---

Essa aplicação precisa ser executada utilizando o container Docker então o próximo passo é fazer a criação do Dockerfile e do Docker Compose. 
- Analise o projeto para entender as tecnologias e dependências
- O Dockerfile deve seguir as boas práticas
- O Docker compose será utilizado para desenvolvimento

Boas práticas
- Não utilizar multi stage build em projetos nodejs
- No Docker compose sempre que utilizar volumes, utilize bind mount para a pasta .docker_vol na raiz do projeto

---
# Criar Manifestos Kubernetes
A aplicação precisa ser executada dentro de um cluster Kubernetes.
Eu já tenho, no meu projeto, o Dockerfile e o docker-compose. Agora eu quero criar os manifestos Kubernetes com base nas características do projeto e com base no docker-compose. Então utilize o docker-compose como referência e qualquer dependência externa à aplicação deve ser criada também como um manifesto de um serviço que vai ser executado no Kubernetes 

Salve os menifestos dentro da pasta k8s.


# Criar Relarorios ambiente Kubernetes

Crie um relatorio do meu cluster Kubernetes
  O relatorio deve ter os seguintes topicos
  - Inventário de Hardware
  - Pods em execuçaão
  - Aplicações em execução
  - Status de saúde do cluster e das aplicações
  - Sugestões de melhorias
