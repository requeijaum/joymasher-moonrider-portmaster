/* Moonrider muOS render-only frameskip shim.
 * Port-owned document-start patch: no commercial game files are modified.
 */
(function (root) {
  'use strict';

  if (root.MUOSFrameskip) return;

  var state = {
    runtime: null,
    settings: null,
    localization: null,
    active: 0,
    override: parseSkip(root.MOONRIDER_FRAMESKIP_OVERRIDE),
    phase: 0,
    skipThisDraw: false,
    ticks: 0,
    drawn: 0,
    skipped: 0,
    lastLayout: null,
    menuPoll: null,
    installed: false
  };

  function parseSkip(value) {
    if (value === null || typeof value === 'undefined' || value === '') return null;
    var parsed = Number(value);
    if (!isFinite(parsed)) return null;
    parsed = Math.floor(parsed);
    return parsed >= 0 && parsed <= 3 ? parsed : null;
  }

  function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
  }

  function instances(runtime) {
    var result = [];
    var types = runtime.types_by_index || [];
    for (var i = 0; i < types.length; i++) {
      var list = types[i] && types[i].instances;
      if (!list) continue;
      for (var j = 0; j < list.length; j++) result.push(list[j]);
    }
    return result;
  }

  function findDictionaries(runtime) {
    var list = instances(runtime);
    for (var i = 0; i < list.length; i++) {
      var dictionary = list[i] && list[i].dictionary;
      if (!dictionary) continue;
      if (hasOwn(dictionary, 'settings_screenmode')) state.settings = dictionary;
      if (hasOwn(dictionary, 'varOptSCREENMODE')) state.localization = dictionary;
    }
    return !!state.settings;
  }

  function patchMenuDefinitions() {
    var dictionary = state.localization;
    if (dictionary) {
      dictionary.varOptSCREENMODE = 'OFF,1,2,3';
      if (typeof dictionary.menuOPTIONS === 'string') {
        dictionary.menuOPTIONS = dictionary.menuOPTIONS.replace(
          /idSCREENMODE-varOptSCREENMODE,[^;]*/g,
          'idSCREENMODE-varOptSCREENMODE,FRAME SKIP'
        );
      }
    }

    var list = instances(state.runtime);
    var shown = String(state.active);
    for (var i = 0; i < list.length; i++) {
      var instance = list[i];
      var vars = instance && instance.instance_vars;
      if (!vars) continue;
      if (vars.indexOf('idSCREENMODE-varOptSCREENMODE') !== -1) {
        instance.text = 'FRAME SKIP';
        if (typeof instance.set_bbox_changed === 'function') instance.set_bbox_changed();
      }
      if (vars.indexOf('idSCREENMODE') !== -1) {
        if (vars.length > 2) vars[2] = 'OFF,1,2,3';
        instance.text = state.active === 0 ? 'OFF' : shown;
        if (typeof instance.set_bbox_changed === 'function') instance.set_bbox_changed();
      }
    }
  }

  function startMenuDiscovery() {
    if (state.localization || state.menuPoll !== null) return;
    var attempts = 0;
    state.menuPoll = root.setInterval(function () {
      attempts++;
      findDictionaries(state.runtime);
      if (state.localization) {
        patchMenuDefinitions();
        root.clearInterval(state.menuPoll);
        state.menuPoll = null;
      } else if (attempts >= 1200) {
        root.clearInterval(state.menuPoll);
        state.menuPoll = null;
      }
    }, 100);
    if (state.menuPoll && typeof state.menuPoll.unref === 'function') {
      state.menuPoll.unref();
    }
  }

  function layoutName(runtime) {
    var layout = runtime.running_layout;
    return layout ? (layout.name || layout.sid || layout) : null;
  }

  function requestedSkip() {
    if (state.override !== null) return state.override;
    var selected = parseSkip(state.settings.settings_screenmode);
    return selected === null ? 0 : selected;
  }

  function reconcile(force) {
    var next = requestedSkip();
    var layout = layoutName(state.runtime);
    if (!force && next === state.active && layout === state.lastLayout) return;

    state.active = next;
    state.lastLayout = layout;
    state.phase = 0;
    state.skipThisDraw = false;
    state.runtime.redraw = true;
    patchMenuDefinitions();

    if (root.console && typeof root.console.log === 'function') {
      root.console.log('[muos-frameskip] active=' + state.active +
        (state.override === null ? ' source=menu' : ' source=fixed'));
    }
  }

  function wrapDraw(methodName) {
    var runtime = state.runtime;
    var original = runtime[methodName];
    if (typeof original !== 'function') return;

    runtime[methodName] = function () {
      if (state.skipThisDraw) {
        state.skipped++;
        this.redraw = true;
        return;
      }
      state.drawn++;
      return original.apply(this, arguments);
    };
  }

  function install(runtime) {
    if (state.installed || !runtime || runtime.isloading) return false;
    if (typeof runtime.tick !== 'function' || !findDictionaries(runtime)) return false;

    state.runtime = runtime;
    var originalTick = runtime.tick;
    wrapDraw('drawGL');
    wrapDraw('draw');

    runtime.tick = function (backgroundWake, timestamp, debugStep) {
      reconcile(false);
      if (!backgroundWake && !debugStep) {
        state.ticks++;
        state.skipThisDraw = state.active > 0 && state.phase !== 0;
        state.phase = (state.phase + 1) % (state.active + 1);
      } else {
        state.skipThisDraw = false;
      }
      return originalTick.apply(this, arguments);
    };

    state.installed = true;
    reconcile(true);
    startMenuDiscovery();
    return true;
  }

  root.MUOSFrameskip = {
    getState: function () {
      return {
        installed: state.installed,
        active: state.active,
        override: state.override,
        phase: state.phase,
        ticks: state.ticks,
        drawn: state.drawn,
        skipped: state.skipped,
        layout: state.lastLayout
      };
    },
    setOverride: function (value) {
      state.override = parseSkip(value);
      root.MOONRIDER_FRAMESKIP_OVERRIDE = state.override;
      if (state.installed) reconcile(true);
    }
  };

  var poll = root.setInterval(function () {
    var runtime = typeof root.cr_getC2Runtime === 'function'
      ? root.cr_getC2Runtime()
      : null;
    if (install(runtime)) root.clearInterval(poll);
  }, 10);
  if (poll && typeof poll.unref === 'function') poll.unref();
}(typeof window !== 'undefined' ? window : globalThis));
