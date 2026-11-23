// Gerador do experimento oficial (playbook §9; ADR 0009, W6). Modelo aberto: taxa de chegada fixa por fase
// (ramping-arrival-rate), para não esconder a lentidão da plataforma (coordinated omission).
//
// Cada iteração é uma mensagem nova de um cliente sintético. Conversas "tagarelas": ~8 mensagens por cliente.
// Com probabilidade REDELIVER, a iteração também reenvia uma mensagem anterior (1 a 20 posições atrás), fora de
// ordem, como um canal que repete o webhook. Tudo determinístico pela SEED e pelo número da iteração.
//
// Variáveis: BASE_URL, SECRET, RUN, SEED, REDELIVER, BASE_RATE (1× em mensagens/s) e STAGES
// ("nome:multiplicador:segundos;..."; sem aspas, para passar intacto pela linha de comando do Windows).
import crypto from "k6/crypto";
import exec from "k6/execution";
import http from "k6/http";

const BASE_URL = __ENV.BASE_URL || "http://api:3000";
const SECRET = (__ENV.SECRET || "dev-channel-secret").split(",")[0];
const RUN = __ENV.RUN || "manual";
const SEED = Number(__ENV.SEED || 42);
const REDELIVER = Number(__ENV.REDELIVER || 0.3);
const BASE_RATE = Number(__ENV.BASE_RATE || 5);
const STAGES = (__ENV.STAGES || "1x:1:120;10x:10:300;50x:50:180;1x-volta:1:120")
  .split(";")
  .map((stage) => stage.split(":"))
  .map(([name, multiplier, seconds]) => [name, Number(multiplier), Number(seconds)]);
const RAMP_SECONDS = 5;

const EXPECTED = STAGES.reduce((sum, [, multiplier, seconds]) => sum + multiplier * BASE_RATE * seconds, 0);
const CUSTOMERS = Math.max(1, Math.ceil(EXPECTED / 8));
const CHANNELS = ["app_chat", "whatsapp", "email"];
const TEXTS = {
  infinitepay: [
    "minha maquininha não liga",
    "não recebi meu repasse de ontem",
    "quero aumentar meu limite de crédito",
    "o pix caiu duas vezes, cobraram R$ AMOUNT",
    "preciso de um empréstimo de R$ AMOUNT",
    "como emito a segunda via do boleto?",
    "quero falar com um atendente",
  ],
  jim: [
    "my card reader won't turn on",
    "where is my payout?",
    "I need a loan of US$ AMOUNT",
    "I was charged twice, $AMOUNT",
    "how do I update my bank account?",
    "I want to talk to a person",
  ],
};

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ["p(50)", "p(95)", "p(99)", "max"],
  scenarios: {
    webhooks: {
      executor: "ramping-arrival-rate",
      startRate: STAGES[0][1] * BASE_RATE,
      timeUnit: "1s",
      preAllocatedVUs: Number(__ENV.PRE_VUS || 200),
      maxVUs: Number(__ENV.MAX_VUS || 2000),
      stages: STAGES.flatMap(([, multiplier, seconds]) => [
        { target: multiplier * BASE_RATE, duration: `${RAMP_SECONDS}s` },
        { target: multiplier * BASE_RATE, duration: `${seconds - RAMP_SECONDS}s` },
      ]),
    },
  },
};

// Gerador pseudoaleatório pequeno e determinístico (mulberry32).
function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function message(index) {
  const next = random(SEED * 1000003 + index);
  const customer = Math.floor(next() * CUSTOMERS);
  const brand = customer % 10 < 7 ? "infinitepay" : "jim";
  const texts = TEXTS[brand];
  const text = texts[Math.floor(next() * texts.length)].replace("AMOUNT", String(100 + Math.floor(next() * 20000)));
  return {
    channel: CHANNELS[customer % CHANNELS.length],
    body: JSON.stringify({
      provider_message_id: `k6-${RUN}-${index}`,
      brand,
      customer: { external_id: `k6-${RUN}-c${customer}` },
      text,
    }),
    pmid: `k6-${RUN}-${index}`,
    next,
  };
}

function send(item, redelivery) {
  const id = `${item.pmid}-${redelivery ? "r" : "o"}-${exec.scenario.iterationInTest}`;
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = `v1=${crypto.hmac("sha256", SECRET, `${id}.${timestamp}.${item.body}`, "hex")}`;
  http.post(`${BASE_URL}/webhooks/channels/${item.channel}`, item.body, {
    headers: {
      "Content-Type": "application/json",
      "X-Webhook-Id": id,
      "X-Webhook-Timestamp": String(timestamp),
      "X-Webhook-Signature": signature,
    },
    tags: { pmid: item.pmid, channel: item.channel, redelivery: String(redelivery), name: "webhook" },
    timeout: "10s",
  });
}

export default function () {
  const index = exec.scenario.iterationInTest;
  const item = message(index);
  send(item, false);
  if (index > 0 && item.next() < REDELIVER) {
    const back = 1 + Math.floor(item.next() * 20);
    send(message(Math.max(0, index - back)), true);
  }
}
