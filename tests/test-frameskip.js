'use strict';

const assert = require('assert');
const path = require('path');

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

global.window = global;
global.MOONRIDER_FRAMESKIP_OVERRIDE = undefined;

const settings = {
  settings_screenmode: 1
};
const localization = {
  menuOPTIONS: 'idSHOWFPS-varOptONOFF,SHOW FPS;idSCREENMODE-varOptSCREENMODE,SCREEN MODE;idBACK,BACK',
  varOptSCREENMODE: 'FULL,WINDOW X1,WINDOW X2,WINDOW X3'
};
const label = {
  text: 'SCREEN MODE',
  instance_vars: [0, 'stageselect_desc', '', '', 0, 0, 0, 'idSCREENMODE-varOptSCREENMODE']
};
const value = {
  text: 'FULL',
  instance_vars: [0, 'ON,OFF', 'FULL,WINDOW X1,WINDOW X2,WINDOW X3', 0, 'idSCREENMODE', 'varOptSCREENMODE']
};

const runtime = {
  isloading: false,
  running_layout: { name: 'stage1-1' },
  redraw: true,
  logicTicks: 0,
  nativeDraws: 0,
  tick(backgroundWake, timestamp, debugStep) {
    this.logicTicks++;
    this.redraw = true;
    if (this.redraw && !backgroundWake) {
      this.redraw = false;
      this.drawGL();
    }
  },
  drawGL() {
    this.nativeDraws++;
  },
  draw() {
    this.nativeDraws++;
  },
  types_by_index: [
    { instances: [{ dictionary: settings }] },
    { instances: [{ dictionary: localization }] },
    { instances: [label] },
    { instances: [value] }
  ]
};

global.cr_getC2Runtime = () => runtime;

(async () => {
  require(path.resolve(__dirname, '../moonrider/patches/muos_frameskip.js'));
  await sleep(80);

  assert(global.MUOSFrameskip, 'shim must expose diagnostics API');
  assert.strictEqual(localization.varOptSCREENMODE, 'OFF,1,2,3');
  assert(localization.menuOPTIONS.includes('idSCREENMODE-varOptSCREENMODE,FRAME SKIP'));
  assert.strictEqual(label.text, 'FRAME SKIP');
  assert.strictEqual(value.text, '1');
  assert.strictEqual(value.instance_vars[2], 'OFF,1,2,3');

  for (let i = 0; i < 4; i++) runtime.tick(false, i * 16.67, false);
  assert.strictEqual(runtime.logicTicks, 4, 'frameskip must not suppress logic ticks');
  assert.strictEqual(runtime.nativeDraws, 2, 'skip=1 must draw every second tick');
  assert.strictEqual(runtime.redraw, true, 'a skipped draw must preserve pending redraw');

  let state = global.MUOSFrameskip.getState();
  assert.strictEqual(state.active, 1);
  assert.strictEqual(state.drawn, 2);
  assert.strictEqual(state.skipped, 2);

  settings.settings_screenmode = 2;
  runtime.tick(false, 100, false);
  assert.strictEqual(runtime.nativeDraws, 3, 'setting change must reset cadence and draw immediately');
  for (let i = 0; i < 5; i++) runtime.tick(false, 116 + i * 16.67, false);
  state = global.MUOSFrameskip.getState();
  assert.strictEqual(state.active, 2);
  assert.strictEqual(state.drawn, 4, 'skip=2 must draw one of every three ticks');
  assert.strictEqual(state.skipped, 6);
  assert.strictEqual(value.text, '2');

  global.MUOSFrameskip.setOverride(3);
  for (let i = 0; i < 4; i++) runtime.tick(false, 220 + i * 16.67, false);
  state = global.MUOSFrameskip.getState();
  assert.strictEqual(state.active, 3, 'fixed override must take precedence over menu state');
  assert.strictEqual(state.override, 3);
  assert.strictEqual(value.text, '3');
  assert.strictEqual(state.drawn, 5, 'skip=3 must draw one of every four ticks');

  global.MUOSFrameskip.setOverride(null);
  runtime.running_layout = { name: 'stage1-2' };
  runtime.tick(false, 300, false);
  state = global.MUOSFrameskip.getState();
  assert.strictEqual(state.active, 2);
  assert.strictEqual(state.drawn, 6, 'layout change must reset cadence and draw immediately');

  console.log('test-frameskip: OK');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
