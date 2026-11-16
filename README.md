# petServices no Kubernetes

Manifests para rodar os 3 serviços (petServices, Agendamento, HistoricoApi) com
PostgreSQL e Kafka dentro do mesmo cluster.

```
base/   → todos os manifests (usado direto no kind)
aks/    → base/ com as imagens do ACR + Gateway (HTTPS) + emissor Let's Encrypt
cert-manager/ → instalacao do cert-manager (certificados HTTPS)

cluster
├── namespace infra        → postgres (StatefulSet + disco), kafka (StatefulSet + disco)
└── namespace petservices  → petservices, agendamento, historico (Deployment + Service)
```

## Subir no kind (local)

```bash
# 1. construir as imagens (a partir da pasta estudos2026)
docker build -t petservices:0.1 petServices
docker build -t agendamento:0.1 Agendamento
docker build -t historico:0.1 HistoricoApi

# 2. colocar as imagens dentro do cluster kind
kind load docker-image petservices:0.1 agendamento:0.1 historico:0.1 --name estudos

# 3. criar os Secrets (UMA vez por cluster) e aplicar tudo
./criar-secrets.sh admin@petservices.dev
kubectl apply -k base

# 4. acompanhar os pods subindo
kubectl get pods -A -w
```

Para acessar uma API da sua máquina:

```bash
kubectl port-forward -n petservices svc/petservices 8081:8081
# em outro terminal: curl localhost:8081/actuator/health
```

## Subir no AKS

```bash
az acr login -n acrpetservicesexemplo
docker tag petservices:0.1 acrpetservicesexemplo.azurecr.io/petservices:0.1   # idem agendamento e historico
docker push acrpetservicesexemplo.azurecr.io/petservices:0.1
kubectl config use-context aks-petservices
./criar-secrets.sh email-do-admin
kubectl apply -k cert-manager   # uma vez; espere os pods do namespace cert-manager ficarem Ready
kubectl apply -k aks
```

## Comandos para estudar

| Comando | O que mostra |
|---|---|
| `kubectl get pods -n petservices` | os pods e quantas vezes reiniciaram |
| `kubectl describe pod <nome> -n petservices` | eventos: por que reiniciou, probes falhando |
| `kubectl logs -n petservices deploy/agendamento -f` | logs da API ao vivo |
| `kubectl delete pod -n petservices -l app=historico` | mata o pod e veja o Deployment recriar sozinho |
| `kubectl scale deploy/agendamento -n petservices --replicas=2` | duas cópias atrás do mesmo Service |
| `kubectl get pvc -n infra` | os discos do Postgres e do Kafka |
| `kubectl exec -it postgres-0 -n infra -- psql -U postgres` | entrar no banco |

## Atualizar uma API depois de mudar o código

```bash
docker build -t agendamento:0.2 Agendamento
kind load docker-image agendamento:0.2 --name estudos
kubectl set image deploy/agendamento agendamento=agendamento:0.2 -n petservices
kubectl rollout status deploy/agendamento -n petservices   # rolling update
kubectl rollout undo deploy/agendamento -n petservices     # se der errado, volta
```

## Apagar tudo

```bash
kubectl delete -k base   # (no AKS: kubectl delete -k aks)
# os discos (PVC) dos StatefulSets continuam; apague com:
kubectl delete pvc --all -n infra
```

## CI/CD (GitHub Actions)

```
push na main de uma API ──► testes ──► imagem <commit> no ACR ──► commit trocando newTag em aks/kustomization.yaml
                                                                       └──► deploy.yml deste repo ──► kubectl apply -k aks
```

- Login na Azure sem senha (OIDC): `./configurar-github-oidc.sh` cria as identidades (uma vez).
- Os workflows das APIs precisam do secret `K8S_REPO_TOKEN` (token com escrita neste repositorio).
- Como o GitHub Actions faz commits aqui, rode `git pull` antes de editar.
