/*
 * muos_gamepad_shim.js — v3 auditado (latch de release correto)
 * Injeta navigator.getGamepads() no WebView WPE para o Construct 2 (plugin Gamepad).
 *
 * MUDANÇA-CHAVE vs v1: o pad é reportado como CONECTADO desde o boot. NÃO há mais
 * estado "adormecido" que exigia um 1º aperto para o C2 enxergar o controle — isso
 * criava dependência circular com o input físico (que podia não chegar). Agora o
 * gamepadconnected dispara na instalação e getGamepads() sempre devolve o pad.
 *
 * Layout STANDARD (W3C). O launcher nativo (evdev_gamepad.c) empurra o estado já
 * traduzido para índices standard via window.__muos_pushGamepad(btnState, axState).
 */
(function () {
  "use strict";
  if (window.__muos_gamepad_installed) return;
  window.__muos_gamepad_installed = true;
  var DEBUG = !!window.__muos_debug;

  var NBTN = 17;   // 0..15 standard + 16 = guide (opcional)
  var NAXES = 4;   // LX LY RX RY

  function makeButtons() {
    var a = new Array(NBTN);
    for (var i = 0; i < NBTN; i++) a[i] = { value: 0, pressed: false, touched: false };
    return a;
  }
  function makeAxes() {
    var a = new Array(NAXES);
    for (var i = 0; i < NAXES; i++) a[i] = 0;
    return a;
  }
  function makePad(index) {
    return {
      id: "muOS RG40xx H (Standard)",
      index: index,
      connected: true,
      mapping: "standard",
      timestamp: 0,
      buttons: makeButtons(),
      axes: makeAxes()
    };
  }

  // 1 pad single-player, CONECTADO desde o inicio (sem quirk awake).
  var pads = [ makePad(0), null, null, null ];

  var BTN_NAMES = ["A","B","X","Y","L1","R1","L2","R2","SELECT","START","L3","R3","UP","DOWN","LEFT","RIGHT","GUIDE"];
  var prevBtn = new Array(NBTN); for (var _i=0;_i<NBTN;_i++) prevBtn[_i]=0;

  // LATCH anti-borda-perdida: com tick do C2 irregular (~27fps) e push a 60Hz, o C2 pode
  // ler getGamepads() DEPOIS de o botao ja ter voltado a 0 -> perde a borda OnButtonDown
  // (sintoma: menu SAVEMANAGE nao fechava apesar de A ser apertado 63x). O latch segura
  // pressed=true por ate LATCH_READS leituras do getGamepads apos o release fisico, garantindo
  // que pelo menos 1 tick do C2 veja a transicao 0->1->0 completa.
  var LATCH_READS = 2;
  var latch = new Array(NBTN); for (var _l=0;_l<NBTN;_l++) latch[_l]=0;
  var pendingTraceSeq = 0;
  var lastReadTraceSeq = 0;

  function buttonMask(p) {
    var mask = 0;
    for (var i = 0; i < NBTN; i++) if (p.buttons[i].pressed) mask |= (1 << i);
    return "0x" + ("00000" + mask.toString(16)).slice(-5);
  }

  // getGamepads(): aplica o latch — se o botao fisico soltou mas ainda ha latch, mantem pressed.
  function getGamepads() {
    var p = pads[0];
    if (p) {
      for (var i = 0; i < NBTN; i++) {
        if (latch[i] > 0) {
          latch[i]--;
          p.buttons[i].pressed = true;
          p.buttons[i].value = 1;
        } else if (prevBtn[i] < 0.5) {
          // O launcher só envia quando o evdev muda. Portanto o próprio polling
          // precisa soltar o botão quando o latch expira; não haverá outro push.
          p.buttons[i].pressed = false;
          p.buttons[i].value = 0;
        }
      }
      if (pendingTraceSeq && pendingTraceSeq !== lastReadTraceSeq) {
        lastReadTraceSeq = pendingTraceSeq;
        if (window.console && console.log) {
          console.log("MUOS_PAD_READ seq=" + pendingTraceSeq + " mask=" + buttonMask(p));
        }
      }
    }
    return pads;
  }
  navigator.getGamepads = getGamepads;
  navigator.webkitGetGamepads = getGamepads;

  // API nativa chamada pelo launcher C: btnState[17] 0..1, axState[4] -1..1.
  window.__muos_pushGamepad = function (btnState, axState, traceSeq) {
    var p = pads[0];
    if (!p) { p = pads[0] = makePad(0); }
    var i;
    for (i = 0; i < NBTN; i++) {
      var v = (btnState && i < btnState.length) ? +btnState[i] : 0;
      if (v >= 0.5 && prevBtn[i] < 0.5) {
        if (DEBUG && window.console && console.log) console.log("MUOS_BTN_DOWN", BTN_NAMES[i] || i);
      } else if (v < 0.5 && prevBtn[i] >= 0.5) {
        // Armar na borda de RELEASE. Armar no press consumia todo o latch enquanto
        // o botão ainda estava fisicamente pressionado e perdia a borda depois.
        latch[i] = LATCH_READS;
      }
      prevBtn[i] = v;
      // se fisicamente pressed, reflete direto; se soltou, o latch (no getGamepads) segura.
      if (v >= 0.5) { p.buttons[i].value = v; p.buttons[i].pressed = true; }
      else if (latch[i] <= 0) { p.buttons[i].value = 0; p.buttons[i].pressed = false; }
    }
    for (i = 0; i < NAXES; i++) {
      p.axes[i] = (axState && i < axState.length) ? +axState[i] : 0;
    }
    p.timestamp = (window.performance && performance.now) ? performance.now() : Date.now();
    pendingTraceSeq = +traceSeq || 0;
    if (window.console && console.log) {
      console.log("MUOS_PAD_PUSH seq=" + pendingTraceSeq + " mask=" + buttonMask(p));
    }
  };

  // Disparar gamepadconnected IMEDIATAMENTE (o C2 escuta este evento p/ ativar o pad).
  try {
    var ev = new Event("gamepadconnected");
    ev.gamepad = pads[0];
    window.dispatchEvent(ev);
  } catch (e) { /* Event.gamepad pode ser read-only; C2 tb faz polling via getGamepads */ }

  if (window.console && console.log) console.log("MUOS_GAMEPAD_SHIM_INSTALLED_V3");
})();
