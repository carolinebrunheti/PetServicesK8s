# Testes de carga e tolerância a falhas

`fluxo.js` simula o uso real: login → cadastra dono e pet → agenda consulta → consulta o histórico.
Além do tempo das requisições, ele mede quanto tempo os eventos levam para atravessar o Kafka:

| Métrica | O que é |
|---|---|
| `propagacao_cadastro_ms` | do cadastro do pet no PetServices até o Agendamento conhecê-lo |
| `propagacao_historico_ms` | do agendamento até a consulta aparecer no Historico |
| `eventos_nao_chegaram` | eventos que não chegaram em 30 s (evento perdido!) |
| `http_req_duration{etapa:...}` | tempo de cada etapa: login, cadastro, listar, agendar, historico |

## Rodar

```bash
cd testes-carga
export ADMIN_EMAIL=email-do-admin ADMIN_SENHA='senha-do-admin'

TIPO=smoke  k6 run fluxo.js    # 1 usuario, 1 min: o script e o ambiente funcionam?
TIPO=load   k6 run fluxo.js    # 20 usuarios por 10 min: comportamento normal
TIPO=stress k6 run fluxo.js    # ate 150 usuarios: onde quebra?
TIPO=spike  k6 run fluxo.js    # de 5 para 100 usuarios em 10 s
TIPO=soak DURACAO=60m k6 run fluxo.js   # carga media por muito tempo: vazamento de memoria?
```

Cada rodada cria dados reais (donos, pets, consultas e um veterinário com nomes começando com `k6`).

## Observar enquanto roda (em outros terminais)

```bash
kubectl get pods -n petservices -w          # reinicios, pods saindo do ar
watch kubectl top pods -A                   # CPU e memoria de cada pod
watch kubectl top nodes                     # o no inteiro (o cluster tem 1 no so)
kubectl logs -n petservices deploy/historico -f
kubectl port-forward -n infra svc/kafka-ui 8090:8080   # http://localhost:8090 → consumer lag
```

## Carga + falha (o experimento mais interessante)

Com o `TIPO=load` rodando, provoque uma falha no meio e veja o impacto no resultado do k6:

```bash
kubectl delete pod -n petservices -l app=agendamento        # 1. mata uma API
kubectl scale statefulset kafka -n infra --replicas=0        # 2. derruba o Kafka (volte com --replicas=1)
kubectl scale deploy historico -n petservices --replicas=0   # 3. para um consumidor (volte com --replicas=1)
```

Antes de cada um, anote a hipótese: quantos erros? Por quanto tempo? Algum evento se perde?
