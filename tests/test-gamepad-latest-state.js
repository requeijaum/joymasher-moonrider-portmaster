#!/usr/bin/env node
"use strict";

const path = require("path");
global.window = global;
global.navigator = {};
global.Event = function Event(type) { this.type = type; };
global.dispatchEvent = function () {};
global.__muos_debug = false;
require(path.resolve(__dirname, "../moonrider/patches/muos_gamepad_shim.js"));

function buttons(...pressed) {
  const a = new Array(17).fill(0);
  for (const i of pressed) a[i] = 1;
  return a;
}
function edges(...pressed) { return buttons(...pressed); }
const axes = [0, 0, 0, 0];
const pad = () => navigator.getGamepads()[0];

// Physical hold is immediate and continuous; its queued edge is consumed by read.
__muos_pushGamepad(buttons(0), axes, edges(0), 1);
if (!pad().buttons[0].pressed) throw new Error("physical A press was lost");
if (!pad().buttons[0].pressed) throw new Error("physical A hold was not continuous");
__muos_pushGamepad(buttons(), axes, edges(), 2);
if (pad().buttons[0].pressed) throw new Error("physical A release was latched");

// A complete short tap coalesced in C arrives neutral plus its rising edge.
__muos_pushGamepad(buttons(), axes, edges(0), 5);
let p = pad();
if (!p.buttons[0].pressed) throw new Error("coalesced A tap was lost");
p = pad();
if (p.buttons[0].pressed) throw new Error("synthetic A did not release after one read");

// Two historical taps are serialized with a neutral read; never fabricate A+B.
__muos_pushGamepad(buttons(), axes, edges(0, 1), 6);
p = pad();
if (!p.buttons[0].pressed || p.buttons[1].pressed) throw new Error("first synthetic tap was not isolated");
p = pad();
if (p.buttons[0].pressed || p.buttons[1].pressed) throw new Error("neutral separator missing");
p = pad();
if (p.buttons[0].pressed || !p.buttons[1].pressed) throw new Error("second synthetic tap was not isolated");
p = pad();
if (p.buttons[0].pressed || p.buttons[1].pressed) throw new Error("second synthetic release missing");

// A stale callback cannot regress the current state.
__muos_pushGamepad(buttons(2), axes, edges(2), 4);
p = pad();
if (p.buttons[2].pressed) throw new Error("stale sequence regressed gamepad state");

// New physical state still wins over any synthetic queue.
__muos_pushGamepad(buttons(2), axes, edges(2), 7);
if (!pad().buttons[2].pressed || !pad().buttons[2].pressed)
  throw new Error("physical X hold failed after synthetic taps");
__muos_pushGamepad(buttons(), axes, edges(), 8);
if (pad().buttons[2].pressed) throw new Error("physical X release stuck");

console.log("test-gamepad-latest-state: OK");
