'use strict';

const assert = require('assert');
const path = require('path');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

global.window = global;
global.MOONRIDER_FRAMESKIP_OVERRIDE = undefined;

const settings = { settings_screenmode: 1 };
const runtime = {
  isloading: false,
  running_layout: { name: 'intrologo' },
  redraw: true,
  tick() {},
  drawGL() {},
  draw() {},
  types_by_index: [{ instances: [{ dictionary: settings }] }]
};
global.cr_getC2Runtime = () => runtime;

(async () => {
  require(path.resolve(__dirname, '../moonrider/patches/muos_frameskip.js'));
  await sleep(50);
  assert(global.MUOSFrameskip.getState().installed, 'shim must install from settings dictionary');

  const localization = {
    menuOPTIONS: 'idSCREENMODE-varOptSCREENMODE,SCREEN MODE;idBACK,BACK',
    varOptSCREENMODE: 'FULL,WINDOW X1,WINDOW X2,WINDOW X3'
  };
  const label = {
    text: 'SCREEN MODE',
    instance_vars: ['idSCREENMODE-varOptSCREENMODE']
  };
  const value = {
    text: 'FULL',
    instance_vars: [0, '', 'FULL,WINDOW X1,WINDOW X2,WINDOW X3', 0, 'idSCREENMODE']
  };
  runtime.types_by_index.push(
    { instances: [{ dictionary: localization }] },
    { instances: [label, value] }
  );

  await sleep(400);
  assert.strictEqual(localization.varOptSCREENMODE, 'OFF,1,2,3');
  assert(localization.menuOPTIONS.includes('idSCREENMODE-varOptSCREENMODE,FRAME SKIP'));
  assert.strictEqual(label.text, 'FRAME SKIP');
  assert.strictEqual(value.text, '1');
  console.log('test-frameskip-late-menu: OK');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
