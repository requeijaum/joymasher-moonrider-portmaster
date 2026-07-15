#!/usr/bin/env node
'use strict';

const assert = require('assert');
const path = require('path');

const messages = [];
global.window = global;
global.location = { pathname: '/tmp/moonrider/game/index.html' };
global.innerWidth = 640;
global.innerHeight = 480;
Object.defineProperty(global, 'navigator', {
  value: {}, writable: true, configurable: true
});
global.webkit = { messageHandlers: {
  muosAudio: { postMessage: m => messages.push(m) },
  muosExit: { postMessage: () => {} }
}};

function Audio() {}
Audio.prototype.acts = {
  PlayByName() {}, Stop() {}, StopAll() {}, SetVolume() {}, SetMasterVolume() {},
  SetPaused() {}, SetSilent() {}, SetLooping() {}, Preload() {}, PreloadByName() {}
};
Audio.prototype.cnds = {
  IsTagPlaying() { return false; },
  OnEnded() { return false; }
};
const instance = { runtime: null };
const runtime = {
  types: { Audio: { plugin: new Audio(), instances: [instance] } },
  trigger() {}, original_width: 428, original_height: 240,
  wantFullscreenScalingQuality: true
};
instance.runtime = runtime;
global.cr = { plugins_: { Audio } };
global.cr_getC2Runtime = () => runtime;

require(path.resolve(__dirname, '../shims/muos_audio_ghost.js'));
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  await sleep(80);
  const AP = Audio.prototype;
  assert.strictEqual(AP.__muos_wrapped, true, 'ghost did not install');

  AP.acts.PlayByName.call(instance, 0, 'mrrun', 0, 0, 'MRRUN');
  assert(messages.some(m => m.startsWith('PLAY|')), 'PLAY not emitted');
  assert.strictEqual(AP.cnds.IsTagPlaying.call(instance, 'MRRUN'), true,
    'active one-shot tag must be reported playing');

  AP.acts.Stop.call(instance, 'MRRUN');
  assert.strictEqual(AP.cnds.IsTagPlaying.call(instance, 'MRRUN'), false,
    'stopped tag must not be reported playing');

  AP.acts.PlayByName.call(instance, 0, 'bikemotor_loop', 0, 0, 'bikemotor_loop');
  assert.strictEqual(AP.cnds.IsTagPlaying.call(instance, 'BIKEMOTOR_LOOP'), true,
    'tag comparison must be case-insensitive');
  await sleep(520);
  assert.strictEqual(AP.cnds.IsTagPlaying.call(instance, 'bikemotor_loop'), false,
    'finished one-shot must stop reporting playing');

  console.log('PASS: audio ghost IsTagPlaying mirrors native voice state');
  process.exit(0);
})().catch(e => { console.error(e.stack || e); process.exit(1); });
