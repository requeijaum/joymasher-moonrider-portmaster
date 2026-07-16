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
const originalOnEnded = Audio.prototype.cnds.OnEnded;
const compiledEndedConditions = [
  { tag: 'musicINTRO', condition: { func: originalOnEnded } },
  { tag: 'elevator_start', condition: { func: originalOnEnded } },
  { tag: 'MR_CHIP_PICKUP', condition: { func: originalOnEnded } }
];
const acceptedEndedTags = [];
const instance = { runtime: null };
const runtime = {
  types: { Audio: { plugin: new Audio(), instances: [instance] } },
  cndsBySid: {
    1: compiledEndedConditions[0].condition,
    2: compiledEndedConditions[1].condition,
    3: compiledEndedConditions[2].condition
  },
  trigger(method, inst) {
    if (method !== originalOnEnded) return false;
    let accepted = false;
    for (const entry of compiledEndedConditions) {
      if (!entry.condition.func.call(inst, entry.tag)) continue;
      acceptedEndedTags.push(entry.tag);
      if (entry.tag === 'musicINTRO')
        Audio.prototype.acts.PlayByName.call(inst, 1, 'genericboss', 1, 0, 'musicLOOP');
      accepted = true;
    }
    return accepted;
  },
  original_width: 428, original_height: 240,
  wantFullscreenScalingQuality: true
};
instance.runtime = runtime;
global.cr = { plugins_: { Audio } };
global.cr_getC2Runtime = () => runtime;

require(path.resolve(__dirname, '../moonrider/patches/muos_audio_ghost.js'));
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  await sleep(80);
  const AP = Audio.prototype;
  assert.strictEqual(AP.__muos_wrapped, true, 'ghost did not install');

  AP.acts.PlayByName.call(instance, 1, 'genericbossintro', 0, 0, 'musicINTRO');
  assert(messages.some(m => m.startsWith('PLAYPAIR|') &&
    m.includes('genericbossintro.ogg|') && m.endsWith('genericboss.ogg')),
  'generic boss intro must atomically schedule the long boss loop');

  await sleep(380);
  assert.deepStrictEqual(acceptedEndedTags, ['musicINTRO'],
    'synthetic OnEnded must patch the condition cached by Construct 2');
  assert.strictEqual(messages.filter(m => m.startsWith('PLAY|') &&
    m.endsWith('/genericboss.ogg')).length, 0,
  'compatibility OnEnded must not restart a loop already scheduled by PLAYPAIR');
  for (const entry of compiledEndedConditions)
    assert.strictEqual(entry.condition.func, originalOnEnded,
      'cached OnEnded condition must be restored after the synthetic trigger');

  const realSetTimeout = global.setTimeout;
  global.setTimeout = (fn, ms) => realSetTimeout(fn, Math.min(ms, 10));
  AP.acts.PlayByName.call(instance, 0, 'elevator_start', 0, 0, 'elevator_start');
  AP.acts.PlayByName.call(instance, 0, 'mr_chip_pickup', 0, 0, 'MR_CHIP_PICKUP');
  global.setTimeout = realSetTimeout;
  await sleep(30);
  assert.deepStrictEqual(acceptedEndedTags,
    ['musicINTRO', 'elevator_start', 'MR_CHIP_PICKUP'],
    'all project OnEnded tags must survive the native audio bridge');
  for (const entry of compiledEndedConditions)
    assert.strictEqual(entry.condition.func, originalOnEnded,
      'all cached conditions must be restored after each synthetic trigger');

  AP.acts.PlayByName.call(instance, 1, 'genoqueenintro', 0, 0, 'musicINTRO');
  assert(messages.some(m => m.startsWith('PLAYPAIR|') &&
    m.includes('genoqueenintro.ogg|') && m.endsWith('genoqueenloop.ogg')),
  'Geno Queen intro must atomically schedule its noncanonical loop name');

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
