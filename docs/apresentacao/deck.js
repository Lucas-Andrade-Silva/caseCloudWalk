// Navegação, vídeos e interações do deck. Sem dependências.
const stage = document.getElementById("stage");
const slides = [...document.querySelectorAll(".s")];
const $ = (id) => document.getElementById(id);
let cur = 0;

function fit() {
  const k = Math.min(innerWidth / 1920, innerHeight / 1080);
  stage.style.transform = `scale(${k}) translate(-50%, -50%)`;
}
addEventListener("resize", fit); fit();

function show(i) {
  cur = Math.max(0, Math.min(slides.length - 1, i));
  slides.forEach((s, k) => s.classList.toggle("on", k === cur));
  const s = slides[cur];
  document.body.classList.toggle("light", s.classList.contains("t-bone"));
  document.body.classList.toggle("green", s.classList.contains("t-green"));
  $("ch").textContent = s.dataset.ch || "";
  $("num").textContent = cur === 0 ? "" : `${String(cur + 1).padStart(2, "0")} / ${slides.length}`;
  $("bar").style.width = `${((cur + 1) / slides.length) * 100}%`;
  $("bar").style.background = s.classList.contains("t-green") ? "#04140e" : s.classList.contains("t-bone") ? "#0e100f" : "";
  // Vídeos: carrega o do slide atual e os do próximo; toca só os do atual.
  slides.forEach((sl, k) => sl.querySelectorAll("video").forEach((v) => {
    const st = Math.max(1, +(v.dataset.start || 0)); // o quadro 0 dos clipes é branco (página carregando)
    if (Math.abs(k - cur) <= 1 && !v.src) v.src = `${v.dataset.src}#t=${st}`;
    if (k === cur) { v.currentTime = st; v.play().catch(() => {}); } else v.pause();
  }));
  history.replaceState(null, "", `#${cur + 1}`);
}

addEventListener("keydown", (e) => {
  if (e.target.matches("input")) return;
  if (["ArrowRight", "ArrowDown", "PageDown", " "].includes(e.key)) { e.preventDefault(); show(cur + 1); }
  else if (["ArrowLeft", "ArrowUp", "PageUp"].includes(e.key)) { e.preventDefault(); show(cur - 1); }
  else if (e.key === "Home") show(0);
  else if (e.key === "End") show(slides.length - 1);
  else if (e.key.toLowerCase() === "f") (document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen()).catch(() => {});
});
$("prev").onclick = () => show(cur - 1);
$("next").onclick = () => show(cur + 1);
stage.addEventListener("click", (e) => { if (!e.target.closest("button, a, input, video, .nd")) show(cur + 1); });
let idle; addEventListener("mousemove", () => { document.body.classList.remove("idle"); clearTimeout(idle); idle = setTimeout(() => document.body.classList.add("idle"), 2000); });
if (new URLSearchParams(location.search).has("static")) document.body.classList.add("static");

// Clipes com começo lento: o laço volta para data-start, não para 0.
document.querySelectorAll("video").forEach((v) => v.addEventListener("timeupdate", () => { const st = Math.max(1, +(v.dataset.start || 0)); if (v.currentTime < st) v.currentTime = st; }));

// IA: derrubar a LLM mostra as regras assumindo.
$("llmkill").onclick = () => {
  const off = $("track").classList.toggle("off");
  $("llmkill").setAttribute("aria-pressed", String(off));
  $("llmtxt").textContent = off ? "Religar a LLM" : "Derrubar a LLM";
};

// ---------- Experimento: seletor de carga (S1, 2026-11-23; faixas entre as 3 rodadas) ----------
const LOAD = [
  { state: ["Estável", "st-ok"], rate: "5 msg/s", ack: "73–425 ms", p50: "259–404 ms", p99: "426–441 ms", bar: 0.22, color: "#1aa878",
    note: "Carga normal. O p99 fica abaixo de meio segundo." },
  { state: ["Atenção", "st-warn"], rate: "49,6 msg/s", ack: "218–223 ms", p50: "602–636 ms", p99: "1,18–1,25 s", bar: 0.61, color: "#d9771f",
    note: "Sustentado. A meta de 1 s no p99 foi refutada por pouco; nenhum invariante quebrou." },
  { state: ["Ruptura", "st-bad"], rate: "~187 msg/s", ack: "8,6–8,9 s", p50: "80–92 s", p99: "110–119 s", bar: 1, color: "#d6334f",
    note: "Pedi 50×; o gerador entregou ~37×. A fila cresce, mas o vigia escala os clientes em vez de perdê-los." },
];
function load(i) {
  const d = LOAD[i];
  document.querySelectorAll("#loadseg button").forEach((b) => b.setAttribute("aria-selected", String(b.dataset.l == i)));
  $("loadr").value = i;
  $("ls-state").textContent = d.state[0]; $("ls-state").className = d.state[1];
  $("lv-rate").textContent = d.rate; $("lv-ack").textContent = d.ack; $("lv-p50").textContent = d.p50; $("lv-p99").textContent = d.p99;
  $("lv-bar").style.width = `${d.bar * 100}%`; $("lv-bar").style.background = d.color;
  $("loadnote").textContent = d.note;
}
$("loadseg").addEventListener("click", (e) => { const b = e.target.closest("button"); if (b) load(+b.dataset.l); });
$("loadr").addEventListener("input", (e) => load(+e.target.value));
load(0);

// ---------- Arquitetura: peças clicáveis e o Kafka que cai ----------
const PIECES = [
  ["Canais", "App, WhatsApp e e-mail chegam como o mesmo evento, por webhook, já com a marca."],
  ["1 · API Rails", "Recebe as mensagens de todos os canais por webhook e confere a assinatura HMAC de cada uma. Deduplica: a mesma mensagem duas vezes vira um atendimento só. Isso é idempotência."],
  ["2 · Postgres", "A fonte da verdade. A mensagem e o evento que avisa a IA são gravados na mesma transação: o outbox transacional. Ou as duas coisas são gravadas, ou nenhuma."],
  ["3 · Relay", "Lê o outbox e publica os eventos na ordem em que foram gravados. Se a entrega falha, faz retry. Entrega at-least-once: cada mensagem chega pelo menos uma vez."],
  ["4 · Broker", "Serviço sem estado. Recebe o webhook assinado do relay e publica no Kafka. Mensagem inválida vai para a DLQ e não trava as outras."],
  ["5 · Apache Kafka", "Feito para volume alto. Desacopla a plataforma do agente e absorve os picos: o consumidor lê no ritmo que consegue atender."],
  ["6 · Agente de IA", "Consome do Kafka e publica a resposta num tópico de volta, que faz o caminho inverso até a API. Nesta versão é um mock determinístico, com modo caos."],
  ["7 · Sidekiq + Redis", "Jobs agendados. A IA ficou 40 s sem responder? Escala para um humano. Resolvido e parado há 30 min? Fecha sozinho."],
  ["8 · Frontend React", "As telas do cliente, do analista, o painel e o mapa vivo."],
  ["9 · Observabilidade", "OpenTelemetry, Prometheus, Grafana e Jaeger: volume, latência e o trace do caminho de cada mensagem."],
];
const nodes = $("nodes");
function pick(k) {
  nodes.querySelectorAll(".nd").forEach((n) => n.classList.toggle("sel", n.dataset.k == k));
  $("ex-t").textContent = PIECES[k][0]; $("ex-p").textContent = PIECES[k][1];
}
nodes.addEventListener("click", (e) => { const n = e.target.closest(".nd"); if (n) pick(+n.dataset.k); });
pick(2);

// Mensagens andando: entram pelo canal, param no Postgres se o Kafka estiver fora e seguem quando ele volta.
const X = { start: 115, pg: 555, agent: 1515, home: 315 };
let down = false, outbox = 0;
const dotsEl = $("dots"), dots = [];
function spawn(x, back = false) { const el = document.createElement("i"); if (back) el.className = "back"; dotsEl.appendChild(el); dots.push({ el, x, back, held: false }); }
$("kill").onclick = () => {
  down = !down;
  $("kill").setAttribute("aria-pressed", String(down));
  $("killtxt").textContent = down ? "Religar o Kafka" : "Derrubar o Kafka";
  nodes.querySelector(".kf").classList.toggle("down", down);
  pick(down ? 2 : 5);
};
let last = performance.now(), acc = 0, drainAcc = 0;
function tick(t) {
  const dt = Math.min(0.05, (t - last) / 1000); last = t;
  if (slides[cur]?.classList.contains("arch")) {
    acc += dt; if (acc > 0.7) { acc = 0; spawn(X.start); }
    if (!down && outbox > 0) { drainAcc += dt; if (drainAcc > 0.18) { drainAcc = 0; outbox--; spawn(X.pg + 1); } }
    for (let i = dots.length - 1; i >= 0; i--) {
      const d = dots[i];
      const prev = d.x;
      if (d.back) d.x -= 420 * dt; else d.x += 300 * dt;
      if (!d.back && down && prev < X.pg && d.x >= X.pg) { d.el.remove(); dots.splice(i, 1); outbox++; continue; }
      if (!d.back && d.x >= X.agent) { d.el.remove(); dots.splice(i, 1); spawn(X.agent, true); continue; }
      if (d.back && d.x <= X.home) { d.el.remove(); dots.splice(i, 1); continue; }
      d.el.style.transform = `translateX(${d.x - 7}px)`;
      if (d.back) d.el.style.top = "189px";
    }
    const em = $("outbox"); em.textContent = outbox; em.classList.toggle("hot", outbox > 0);
  }
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);

const fromHash = () => (parseInt(location.hash.slice(1), 10) || 1) - 1;
addEventListener("hashchange", () => { if (fromHash() !== cur) show(fromHash()); });
show(fromHash());
