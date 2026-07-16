/*
 * muos_gamepad_shim.js — v4 latest-state (sem replay de backlog)
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
  var physicalBtn = new Array(NBTN); for (var _i=0;_i<NBTN;_i++) physicalBtn[_i]=0;
  var pendingPress = new Array(NBTN); for (var _p=0;_p<NBTN;_p++) pendingPress[_p]=false;
  var pendingOrder = [];
  var syntheticRelease = false;
  var lastSeq = 0;

  function setButton(p, i, value) {
    p.buttons[i].value = value;
    p.buttons[i].pressed = value >= 0.5;
  }

  // O estado físico atual sempre tem prioridade. Rising edges que ocorreram e
  // foram coalescidas no C são apresentadas como pulsos one-shot, uma por leitura,
  // somente quando o pad físico está neutro. A leitura seguinte é obrigatoriamente
  // neutra, impedindo combinações sintéticas A+B e botões presos.
  function getGamepads() {
    var p = pads[0];
    if (!p) return pads;
    var i, anyPhysical = false;
    for (i = 0; i < NBTN; i++) {
      setButton(p, i, physicalBtn[i]);
      if (physicalBtn[i] >= 0.5) anyPhysical = true;
    }

    // Uma edge cujo botão está fisicamente pressionado foi observada diretamente.
    if (pendingOrder.length) {
      var keep = [];
      for (i = 0; i < pendingOrder.length; i++) {
        var queued = pendingOrder[i];
        if (physicalBtn[queued] >= 0.5) pendingPress[queued] = false;
        else keep.push(queued);
      }
      pendingOrder = keep;
    }

    if (anyPhysical) {
      syntheticRelease = false;
    } else if (syntheticRelease) {
      syntheticRelease = false; // esta leitura neutra separa dois taps
    } else if (pendingOrder.length) {
      var button = pendingOrder.shift();
      pendingPress[button] = false;
      setButton(p, button, 1);
      syntheticRelease = true;
      if (DEBUG && window.console && console.log)
        console.log("MUOS_SYNTH_PRESS", BTN_NAMES[button] || button);
    }
    return pads;
  }
  navigator.getGamepads = getGamepads;
  navigator.webkitGetGamepads = getGamepads;

  // API nativa: estado físico mais recente + rising edges preservadas pelo
  // mailbox C + sequência. Sequências antigas nunca podem regredir o pad.
  window.__muos_pushGamepad = function (btnState, axState, pressEdges, seq) {
    var p = pads[0];
    if (!p) { p = pads[0] = makePad(0); }
    var i;
    // Compatibilidade com o launcher V3: terceiro argumento era seq.
    if (typeof pressEdges === "number" && typeof seq === "undefined") {
      seq = pressEdges;
      pressEdges = null;
    }
    seq = +seq;
    if (!(seq > 0)) seq = lastSeq + 1;
    if (seq <= lastSeq) return;
    if (DEBUG && lastSeq > 0 && seq > lastSeq + 1 && window.console && console.log)
      console.log("MUOS_PAD_COALESCED", lastSeq, seq);
    lastSeq = seq;

    for (i = 0; i < NBTN; i++) {
      var v = (btnState && i < btnState.length) ? +btnState[i] : 0;
      physicalBtn[i] = v;
      setButton(p, i, v);
      if (pressEdges && pressEdges[i] && !pendingPress[i]) {
        pendingPress[i] = true;
        pendingOrder.push(i);
      }
    }
    for (i = 0; i < NAXES; i++) {
      p.axes[i] = (axState && i < axState.length) ? +axState[i] : 0;
    }
    p.timestamp = (window.performance && performance.now) ? performance.now() : Date.now();
  };

  // Disparar gamepadconnected IMEDIATAMENTE (o C2 escuta este evento p/ ativar o pad).
  try {
    var ev = new Event("gamepadconnected");
    ev.gamepad = pads[0];
    window.dispatchEvent(ev);
  } catch (e) { /* Event.gamepad pode ser read-only; C2 tb faz polling via getGamepads */ }

  if (window.console && console.log) console.log("MUOS_GAMEPAD_SHIM_INSTALLED_V4_LATEST_STATE");
})();
