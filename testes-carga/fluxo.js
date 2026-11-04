// Teste de carga do fluxo completo: login -> cadastra dono e pet -> agenda consulta -> consulta o historico.
// Alem do tempo de cada requisicao, mede quanto tempo os eventos levam para atravessar o Kafka:
//   PetServices --(pets_eventos/usuarios)--> Agendamento --(agendar_consulta)--> Historico
//
// Uso (veja o README desta pasta):
//   ADMIN_EMAIL=... ADMIN_SENHA=... TIPO=smoke k6 run fluxo.js
import http from 'k6/http';
import exec from 'k6/execution';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'https://petservices-f3c82b.eastus2.cloudapp.azure.com';
const TIPO = __ENV.TIPO || 'smoke';

// tempo ate o pet/dono recem-criado existir no Agendamento (consistencia eventual)
const propagacaoCadastro = new Trend('propagacao_cadastro_ms', true);
// tempo ate a consulta agendada aparecer no Historico
const propagacaoHistorico = new Trend('propagacao_historico_ms', true);
// eventos que nao chegaram dentro do tempo limite: aqui aparece evento perdido
const eventosNaoChegaram = new Counter('eventos_nao_chegaram');

const PERFIS = {
  // 1 usuario: so confere se o script e o ambiente funcionam
  smoke: { executor: 'constant-vus', vus: 1, duration: '1m' },
  // carga "normal": sobe aos poucos e mantem
  load: {
    executor: 'ramping-vus',
    stages: [
      { duration: '2m', target: 20 },
      { duration: '10m', target: 20 },
      { duration: '1m', target: 0 },
    ],
  },
  // aumenta ate quebrar: onde esta o gargalo?
  stress: {
    executor: 'ramping-vus',
    stages: [
      { duration: '3m', target: 25 },
      { duration: '3m', target: 50 },
      { duration: '3m', target: 100 },
      { duration: '3m', target: 150 },
      { duration: '2m', target: 0 },
    ],
  },
  // pico repentino
  spike: {
    executor: 'ramping-vus',
    stages: [
      { duration: '1m', target: 5 },
      { duration: '10s', target: 100 },
      { duration: '2m', target: 100 },
      { duration: '10s', target: 5 },
      { duration: '2m', target: 5 },
    ],
  },
  // carga media por bastante tempo: vazamento de memoria?
  soak: { executor: 'constant-vus', vus: 15, duration: __ENV.DURACAO || '60m' },
};

if (!PERFIS[TIPO]) {
  throw new Error(`TIPO invalido: ${TIPO}. Use: ${Object.keys(PERFIS).join(', ')}`);
}

export const options = {
  scenarios: { [TIPO]: PERFIS[TIPO] },
  // no stress os limites vao estourar de proposito; nos outros eles dizem se o teste passou
  thresholds: TIPO === 'stress' ? {} : {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{etapa:login}': ['p(95)<1500'],
    'http_req_duration{etapa:agendar}': ['p(95)<1000'],
    'http_req_duration{etapa:historico}': ['p(95)<1000'],
    eventos_nao_chegaram: ['count==0'],
  },
};

const JSON_HEADERS = { 'Content-Type': 'application/json' };
// enquanto o evento nao chega, 404 e esperado: nao conta como falha no http_req_failed
const ATE_404 = http.expectedStatuses({ min: 200, max: 299 }, 404);

function login() {
  const r = http.post(`${BASE}/auth/login`,
    JSON.stringify({ email: __ENV.ADMIN_EMAIL, senha: __ENV.ADMIN_SENHA }),
    { headers: JSON_HEADERS, tags: { etapa: 'login' } });
  check(r, { 'login 200': (res) => res.status === 200 });
  return r;
}

// 401 = e-mail/senha errados, 429 = IP bloqueado por logins errados, 400 = e-mail em formato invalido
function motivo(r) {
  let mensagem = r.body;
  try { mensagem = r.json('mensagem') || r.body; } catch (e) { /* corpo nao e JSON */ }
  return `HTTP ${r.status}: ${mensagem}`;
}

function auth(token, etapa, extra = {}) {
  return { headers: { ...JSON_HEADERS, Authorization: `Bearer ${token}` }, tags: { etapa }, ...extra };
}

// repete ate dar certo ou acabar o tempo; devolve [resposta, ms ate dar certo]
function esperar(fn, ok, limiteMs = 30000) {
  const inicio = Date.now();
  let r = fn();
  while (!ok(r) && Date.now() - inicio < limiteMs) {
    sleep(0.5);
    r = fn();
  }
  return [r, Date.now() - inicio];
}

// identificador unico por execucao, para nao repetir e-mail/CRM entre rodadas
const RODADA = Date.now().toString(36);

export function setup() {
  if (!__ENV.ADMIN_EMAIL || !__ENV.ADMIN_SENHA) {
    throw new Error('Defina ADMIN_EMAIL e ADMIN_SENHA');
  }
  const r = login();
  if (r.status !== 200) throw new Error(`Login do admin falhou (${motivo(r)})`);
  const token = r.json('token');

  // um veterinario por rodada; cada consulta usa um horario diferente para nao dar conflito
  const vet = http.post(`${BASE}/veterinario`, JSON.stringify({
    nome: `k6 Vet ${RODADA}`, crm: `K6-${RODADA}`, especialidade: 'Clinico geral',
    email: `k6-vet-${RODADA}@teste.dev`, senha: 'k6-senha-123',
  }), auth(token, 'setup'));
  if (vet.status !== 201) throw new Error(`Cadastro do veterinario falhou: ${vet.status} ${vet.body}`);
  return { vetId: vet.json('id') };
}

export default function ({ vetId }) {
  const r = login();
  if (r.status !== 200) return;
  const token = r.json('token');

  const n = `${RODADA}-${exec.vu.idInTest}-${exec.vu.iterationInScenario}`;

  const dono = http.post(`${BASE}/dono`, JSON.stringify({
    nome: `k6 Tutor ${n}`, email: `k6-${n}@teste.dev`, senha: 'k6-senha-123',
  }), auth(token, 'cadastro'));
  if (!check(dono, { 'dono 201': (r) => r.status === 201 })) return;

  const pet = http.post(`${BASE}/pet`, JSON.stringify({
    nome: `k6 Pet ${n}`, dataNascimento: '2022-01-01', raca: 'SRD',
    especie: 'CACHORRO', donoId: dono.json('id'),
  }), auth(token, 'cadastro'));
  if (!check(pet, { 'pet 201': (r) => r.status === 201 })) return;

  // leitura comum (lista todos os pets: fica mais lenta conforme o banco cresce?)
  check(http.get(`${BASE}/pet`, auth(token, 'listar')), { 'listar pets 200': (r) => r.status === 200 });

  // horario unico: cada iteracao do teste ganha um minuto diferente, daqui a 30 dias
  const dia = new Date(Date.now() + 30 * 24 * 3600 * 1000);
  dia.setUTCHours(0, 0, 0, 0);
  dia.setUTCMinutes(exec.scenario.iterationInTest);
  const diaHora = dia.toISOString().slice(0, 19);

  // o Agendamento responde 404 ate os eventos do dono/pet chegarem pelo Kafka
  const [consulta, msCadastro] = esperar(
    () => http.post(`${BASE}/agendarConsulta`, JSON.stringify({
      tutorId: dono.json('id'), petId: pet.json('id'), veterinarioId: vetId, diaHora,
    }), auth(token, 'agendar', { responseCallback: ATE_404 })),
    (r) => r.status !== 404);
  if (!check(consulta, { 'consulta 201': (r) => r.status === 201 })) {
    if (consulta.status === 404) eventosNaoChegaram.add(1, { evento: 'cadastro' });
    return;
  }
  propagacaoCadastro.add(msCadastro);

  // e o Historico responde 404 ate o evento da consulta chegar
  const consultaId = consulta.json('id');
  const [hist, msHistorico] = esperar(
    () => http.get(`${BASE}/historico/${consultaId}`, auth(token, 'historico', { responseCallback: ATE_404 })),
    (r) => r.status !== 404);
  if (check(hist, { 'historico 200': (r) => r.status === 200 })) {
    propagacaoHistorico.add(msHistorico);
  } else if (hist.status === 404) {
    eventosNaoChegaram.add(1, { evento: 'historico' });
  }

  sleep(1);
}
