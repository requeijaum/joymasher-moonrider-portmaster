/*
 * muos_audio_ghost.js — v12: IPC nativo, PLAYPAIR, pause e SFX polifônicos
 *
 * Arquitetura FINAL (confirmada pelo spike v3): NAO tocar no HTMLMediaElement.prototype
 * (isso travava a engine na tela branca). Interceptar a API de alto nivel do Audio plugin
 * do Construct 2 (cr.plugins_.Audio.prototype.acts.*) e encaminhar cada Play/Stop/Volume
 * para o mixer NATIVO (miniaudio+libvorbis, fora do sandbox) via postMessage.
 *
 * O mixer nativo (launcher, message handler "muosAudio") toca ALSA default->pipewire
 * (caminho que ogg123 provou). Musica (loop/isMusic) = STREAM; SFX = decode/cache.
 *
 * A cena avanca via trigger "On <tag> ended": disparamos apos a duracao REAL do .ogg
 * (tabela ffprobe embutida) OU imediatamente p/ loops (nunca terminam).
 *
 * Path do .ogg: media/ + filename.toLowerCase() + ".ogg" (files_subfolder do C2 = "media/").
 */
(function () {
  "use strict";
  if (window.__muos_audio_ghost_installed) return;
  window.__muos_audio_ghost_installed = true;

  var DEBUG = !!window.__muos_debug;
  function dlog(s) { if (DEBUG) try { console.log(s); } catch (e) {} }
  var MUTE = false; // (window.__muos_audio_mute !== false);
  try { console.log(MUTE ? "MUOS_AUDIO_GHOST_V12_MUTE" : "MUOS_AUDIO_GHOST_V12_IPC"); } catch (e) {}

  // tabela de duracoes reais (ms) por nome de arquivo SEM extensao, lowercase (ffprobe).
  var DUR = {"bc_jetengine1loop":2922,"bc_lasercutterend":491,"bc_rockimpact1":383,"bc_weapon_lasershot_typea_04":1463,"bike_skid":109,"bikemotor_end":474,"bikemotor_loop":429,"bikemotor_start":1005,"boost_ver2":2254,"boss_hydromancer_intro":5581,"boss_hydromancer_loop":101860,"car_engine":4269,"credits_intro":45283,"credits_loop":183396,"cutscene_ending":72727,"cutscene_evil_intro":14884,"cutscene_evil_loop":59535,"cutscene_freedomfighters":112500,"cutscene_freedomfighters_intro":16500,"cutscene_freedomfighters_loop":48000,"cutscene_generic":70161,"cutscene_moonrider_intro":15968,"cutscene_moonrider_loop":30968,"cutscene_nightmare":92160,"cutscene_propaganda_intro":5116,"cutscene_propaganda_loop":29767,"darkchaser_attack":1000,"darkchaser_death":3000,"darkchaser_dialogue":6000,"darkchaser_intro":18947,"darkchaser_laugh_1":1875,"darkchaser_loop":113684,"darkportal_close":312,"darkportal_open":1188,"demo_end_intro":14611,"demo_end_loop":77855,"elevator_loop":1442,"elevator_start":1471,"elevator_stop":1471,"final_boss_intro":14400,"final_boss_phase_1_loop":76800,"final_boss_phase_2_layer_loop":76800,"final_boss_phase_2_loop":76000,"flamestalker_battle_intro":3158,"flamestalker_battle_loop":91579,"flamestalker_death":3000,"flamestalker_dialogue":2000,"flamestalker_powerup":2000,"genericboss":42198,"genericbossintro":330,"genoqueenintro":1846,"genoqueenloop":59077,"geocrusher_death":3000,"geocrusher_dialogue":2000,"geocrusher_intro":11294,"geocrusher_laugh":2625,"geocrusher_loop":120000,"geocrusher_powerup":1250,"giant_laser":1043,"giant_laser_charge":1635,"giant_laser_end":542,"grenade_launcher":519,"grenadelauncherblip":470,"grounddrone_jump":295,"hydro_shuriken_summon":1375,"hydro_shuriken_throw":625,"hydromancer_attack_1":1038,"hydromancer_attack_2":577,"hydromancer_death":3000,"hydromancer_dialogue":4750,"intro_joymasherlogo":4644,"introcutscene_intro":39167,"laserguy_shot":1391,"mechanical_arm":808,"menu":83478,"mr_bigdoorslam":1460,"mr_bigrockimpact":390,"mr_boss_slash1":1154,"mr_boss_slash2":692,"mr_bossbigslash":1154,"mr_chip_pickup":7714,"mr_death":4001,"mr_donutlaser":1332,"mr_doorclose":1301,"mr_doorslam":1415,"mr_dronefire":1636,"mr_dronemachinegunspin":682,"mr_elecwallcharge":621,"mr_elecwallfire":1636,"mr_fire2":308,"mr_flame_boomerang_catch":953,"mr_flame_boomerang_spawn":953,"mr_flame_dash":774,"mr_flame_teleport":1875,"mr_flamestalker_b_slap":1101,"mr_flamestalker_kick":953,"mr_flamestalker_slap":978,"mr_flamestalker_upper":1475,"mr_flamestalker_wallgrab":533,"mr_heavyland":1721,"mr_hydro_teleportin":389,"mr_hydro_teleportout":956,"mr_jet":1343,"mr_leverhit":1029,"mr_menu_gamestart":15809,"mr_menu_goback":1691,"mr_menu_select":2868,"mr_menu_updown":1691,"mr_mine":779,"mr_openingmissile":692,"mr_rank":6231,"mr_roboscream":4615,"mr_roboscream_death":6253,"mr_scream1":607,"mr_scream2":610,"mr_scream4":399,"mr_scream5":2924,"mr_scream5b":2592,"mr_scream6":823,"mr_shootingmissile":692,"mr_slash1":1659,"mr_slash2":351,"mr_slash3":466,"mr_stormdiver_atk1":2538,"mr_stormdiver_atk2_loop":1846,"mr_thunderbg":2132,"mr_titleintro1":1619,"mr_typing":346,"mr_waterdive":1103,"mr_waterlevelchange":3000,"mr_waterstep":221,"mr_waterup":956,"mr_wind":105,"mr_zapping":1053,"mralarm1":1460,"mralarm2":1463,"mrbeam1":2050,"mrbigexplosion":2000,"mrblood1":1659,"mrbreak1":823,"mrcannon2":1858,"mrchakram":1415,"mrchakram2":1415,"mrchakram3":1659,"mrchakramspin":450,"mrcharge1":738,"mrchargecapsule":5303,"mrchargewepintro":621,"mrchargeweploop":207,"mrdamagezap":1053,"mrdoorshut":2192,"mrenemyspinattack":208,"mrenemyswordslash":565,"mrexpl1":1782,"mrexplosion1":1782,"mrexplosion2":1174,"mrfire1":308,"mrgeohit":3692,"mrgeojump":861,"mrgeokick":2381,"mrgeoland":615,"mrgeopunch":2698,"mrgeosmash":3934,"mrgeospinjup":789,"mrgeowave":3400,"mrgore":1112,"mrgun1":533,"mrhang":1485,"mrhit1":1415,"mrhit2":1415,"mritempickup":2406,"mrjump":1495,"mrkick":1562,"mrkunaihit":50,"mrkunaithrow":339,"mrland":2228,"mrlaseraim1":1081,"mrlaseraim2":721,"mrlaserswordattack":1604,"mrlaserswordprep":661,"mrlowslash3":880,"mrmechanism":577,"mrmissiletravel":230,"mrmonster1":572,"mrmonster2":846,"mrplasmaball":1982,"mrplasmashoot2":1126,"mrquickgore":826,"mrrun":741,"mrshieldmounce":177,"mrslash":1659,"mrslash2":1659,"mrslash3":1659,"mrslashcharge":2349,"mrspear":1782,"mrspearcharge":1925,"mrspidermaskclose":242,"mrspidermaskopen":460,"mrspidermissileshoot":411,"mrspiderwalk":738,"mrspinjump":835,"mrspinjump2":783,"mrteleport1":2951,"mrwalk":1054,"mrwalk2":688,"mrwalljump":2092,"ninja_appear":692,"photon_dash":1000,"photondrifter_chargeshot":621,"photondrifter_death":3000,"photondrifter_dialogue":3750,"photondrifter_intro":23294,"photondrifter_land":2228,"photondrifter_loop":90353,"photondrifter_run":741,"piranha_attack":692,"portal_close":448,"portal_open":448,"shinjen_attack":1000,"shinjen_defeat":1875,"shinjen_line_1":7000,"shinjen_line_2":3500,"shinjen_powerup":750,"ship_laser_charge":1846,"ship_laser_shoot":2769,"shipp_appear":5538,"stage_1-1_intro":17143,"stage_1-1_loop":82286,"stage_1-2_intro":4138,"stage_1-2_loop":82759,"stage_2-1_intro":42667,"stage_2-1_loop":149333,"stage_2-2_intro":5333,"stage_2-2_loop":128000,"stage_3-1_intro":13714,"stage_3-1_loop":94286,"stage_3-2_intro":27000,"stage_3-2_loop":84000,"stage_4-1_intro":1500,"stage_4-1_loop":96000,"stage_4-2_intro":17280,"stage_4-2_loop":84480,"stage_5-1_intro":12800,"stage_5-1_loop":89600,"stage_5-2_intro":54545,"stage_5-2_loop":126545,"stage_6-1_intro":40000,"stage_6-1_loop":78400,"stage_6-2_intro":26000,"stage_6-2_loop":76800,"stage_7-1_intro":8640,"stage_7-1_loop":122880,"stage_7-2_intro":33103,"stage_7-2_loop":115862,"stage_8-1_intro":29538,"stage_8-1_loop":88615,"stage_8-2_intro":40000,"stage_8-2_loop":128000,"stage_9-1_intro":45176,"stage_9-1_loop":135529,"stage_clear_intro":25500,"stage_clear_loop":24000,"stage_select_intro":1091,"stage_select_loop":52364,"storm_diver_intro":13714,"storm_diver_loop":123429,"stormdiver_attack_1":375,"stormdiver_attack_2":500,"stormdiver_dialogue":4000,"stormdiver_powerup":1250,"sunseeker_attack_1":500,"sunseeker_attack_2":500,"sunseeker_attack_3":625,"sunseeker_dialogue":4625,"the_end":27170,"tutorial_wip":59077,"tvstatic":1100,"wall_laser":1048,"weapon_error":462,"weapon_menu_open":1385,"weapon_pick":808,"weapon_select":918,"weapon_select2":918};
  function durMsOf(name) {
    var k = ("" + (name || "")).toLowerCase();
    if (DUR.hasOwnProperty(k)) return DUR[k];
    return 1500; // fallback p/ SFX desconhecido
  }

  // canal IPC pro mixer nativo (launcher nao-sandboxed). Em modo MUTE, o ghost
  // preserva a semantica C2/ended/watchdogs, mas nunca acorda o mixer/miniaudio.
  var HAVE_NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.muosAudio);
  function native(msg) {
    if (MUTE) { dlog("MUOS_AUDIO_MUTED " + ("" + msg).split("|")[0]); return false; }
    try {
      if (HAVE_NATIVE) { window.webkit.messageHandlers.muosAudio.postMessage(msg); return true; }
    } catch (e) {}
    return false;
  }
  try { console.log("MUOS_IPC native=" + HAVE_NATIVE + " mute=" + MUTE); } catch (e) {}

  // path absoluto do .ogg no filesystem (o mixer abre via fopen)
  // Deriva de document.location. ATENCAO: o launcher usa load_html com base URI =
  // DIRETORIO com barra final (file:///.../game/), NAO .../index.html.
  // A regex antiga exigia terminar em /arquivo -> falhava com barra final -> caia no
  // fallback sdcard e o mixer procurava .ogg em /mnt/sdcard (inexistente, r=-7, mudo).
  // Agora trata os dois casos: com barra final e com arquivo.
  var MEDIA_BASE = (function() {
    try {
      var loc = window.location.href || "";
      // remove esquema file:// e qualquer query/hash
      var p = loc.replace(/^file:\/\//, "").replace(/[?#].*$/, "");
      if (p) {
        // se terminar em / (diretorio), usa direto; senao, corta o ultimo segmento (arquivo)
        var dir = /\/$/.test(p) ? p.replace(/\/+$/, "") : p.replace(/\/[^\/]*$/, "");
        if (dir) return dir + "/media/";
      }
    } catch (e) {}
    return "/mnt/union/ports/moonrider/game/media/"; // canonical PortMaster fallback
  })();
  function oggPath(name) { return MEDIA_BASE + ("" + name).toLowerCase() + ".ogg"; }

  // O mixer nativo usa id INTEIRO como chave de voz (find_voice(id)). O C2 usa TAG string.
  // Hash estavel tag->int (djb2, sempre positivo) p/ que STOP|<tag> pare a voz certa e
  // SFX de mesma tag reusem a mesma voz (comportamento do C2). Evita 0 (id sentinela).
  function tagId(tag) {
    // Construct 2 audio tags are case-insensitive.
    var s = ("" + (tag || "")).toLowerCase();
    var h = 5381;
    for (var i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    h = h & 0x7fffffff;
    return h === 0 ? 1 : h;
  }

  // dispara o trigger "On <tag> ended" no runtime (a cena avanca por ele).
  // audTag e' closure-privado do plugin -> usamos shim temporario de cnds.OnEnded.
  function fireEndedTag(rt, audioPlugin, tag) {
    try {
      var cr = window.cr;
      var cnds = cr && cr.plugins_ && cr.plugins_.Audio && cr.plugins_.Audio.prototype.cnds;
      if (!cnds || !cnds.OnEnded || !audioPlugin || !rt) return false;
      var origOnEnded = cnds.OnEnded;
      cnds.OnEnded = function (t) { return ("" + t).toLowerCase() === ("" + tag).toLowerCase(); };
      try { rt.trigger(origOnEnded, audioPlugin); }
      finally { cnds.OnEnded = origOnEnded; }
      return true;
    } catch (e) { return false; }
  }

  function findAudioPlugin(rt) {
    try {
      var cr = window.cr;
      for (var k in rt.types) {
        var t = rt.types[k];
        if (t && t.plugin && cr.plugins_ && t.plugin instanceof cr.plugins_.Audio) {
          if (t.instances && t.instances.length) return t.instances[0];
          return t;
        }
      }
    } catch (e) {}
    return null;
  }

  // dbToLinear: o C2 passa volume em dB; converte p/ ganho linear [0..1] p/ o mixer.
  function dbToLinear(db) {
    var v = Math.pow(10, (+db || 0) / 20);
    if (!isFinite(v) || v < 0) v = 0; if (v > 1) v = 1; return v;
  }

  function installActWrappers() {
    try {
      var cr = window.cr;
      if (!cr || !cr.plugins_ || !cr.plugins_.Audio) return false;
      var AP = cr.plugins_.Audio.prototype;
      if (AP.__muos_wrapped) return true;
      if (!AP.acts) return false;
      AP.__muos_wrapped = true;

      var rtRef = null, pluginRef = null;
      function ensureRefs(self) {
        if (!rtRef) rtRef = self.runtime || (window.cr_getC2Runtime && window.cr_getC2Runtime());
        if (!pluginRef && rtRef) pluginRef = findAudioPlugin(rtRef) || self;
      }
      // rastreia voz ativa por id: {name, loop} — evita reiniciar stream de loop ja tocando (engasgo).
      var activeById = {};
      // Token monotônico por execução: invalida timers de uma voz reiniciada/parada.
      // Sem isso, o timer do Play anterior disparava OnEnded no meio do Play novo.
      var generationById = {};
      var playSerial = 0;
      var nextSfxId = -2; // -1 é sentinela de slot livre no mixer C
      var groupVoices = {}; // tagId -> ids únicos de SFX one-shot ativos
      // PLAYPAIR cria duas vozes; parar a intro também deve cancelar o loop agendado.
      var pairLoopByIntro = {};
      // Geração global da música: toda nova ação musicIntro/musicLOOP invalida handoffs antigos.
      // Isso impede um timeout de uma tela anterior de iniciar música atrasada na tela atual.
      var musicEpoch = 0;
      function invalidate(id) { generationById[id] = ++playSerial; }
      function trackGroup(groupId, voiceId) {
        var a = groupVoices[groupId] || (groupVoices[groupId] = []);
        a.push(voiceId);
      }
      function untrackGroup(groupId, voiceId) {
        var a = groupVoices[groupId];
        if (!a) return;
        for (var i = a.length - 1; i >= 0; --i) if (a[i] === voiceId) a.splice(i, 1);
        if (!a.length) delete groupVoices[groupId];
      }
      function eachGroupVoice(groupId, fn) {
        var a = groupVoices[groupId];
        if (!a) return;
        a = a.slice(0);
        for (var i = 0; i < a.length; ++i) fn(a[i]);
      }
      function cancelPairForIntro(introId) {
        var loopId = pairLoopByIntro[introId];
        if (typeof loopId === "undefined") return;
        delete pairLoopByIntro[introId];
        delete activeById[loopId];
        invalidate(loopId);
        native("STOP|" + loopId);
      }
      function stopTimer(id) {
        var st = activeById[id];
        if (st && st.timer) { clearTimeout(st.timer); st.timer = 0; }
      }
      function setVoicePaused(id, paused) {
        var st = activeById[id];
        if (st) {
          if (paused && !st.paused) {
            st.paused = true;
            if (st.timer) {
              clearTimeout(st.timer); st.timer = 0;
              st.remaining = Math.max(0, st.deadline - Date.now());
            }
          } else if (!paused && st.paused) {
            st.paused = false;
            if (st.finish && st.remaining >= 0) {
              st.deadline = Date.now() + st.remaining;
              st.timer = setTimeout(st.finish, st.remaining);
            }
          }
        }
        native("PAUSE|" + id + "|" + (paused ? 1 : 0));
      }
      function doPlay(self, name, isMusic, looping, volDb, tag) {
        ensureRefs(self);
        // BUG FIX: respeitar o 'looping' do C2. NAO forcar loop por isMusic — as faixas
        // 'intro' de musica sao isMusic=true POReM looping=0 (tocam 1x e passam pro _loop).
        var loop = (looping ? 1 : 0);
        var vol = dbToLinear(volDb);
        var groupId = tagId(tag);
        var tagLower = ("" + tag).toLowerCase();
        // ANTI-RESTART: se a MESMA voz (id) ja toca o MESMO arquivo em loop, ignorar o
        // re-Play (o C2 rechama Play todo frame em alguns estados -> reload = engasgo).
        var prev = activeById[groupId];
        if (loop && prev && prev.name === ("" + name).toLowerCase() && prev.loop) {
          dlog("MUOS_PLAY_SKIP id=" + groupId + " tag=" + tag + " (loop ja ativo)");
          return;
        }
        // Uma nova intro substitui qualquer par anterior ainda agendado.
        cancelPairForIntro(groupId);
        if (tagLower === "musicintro" || tagLower === "musicloop") musicEpoch++;
        var oneName = ("" + name).toLowerCase();
        // O C2 permite várias instâncias SFX com a mesma tag. Música é reciclada;
        // SFX one-shot ganha ID nativo único e continua agrupado por tag no JS.
        var polyphonic = !isMusic && !loop;
        var id = polyphonic ? nextSfxId-- : groupId;
        var playToken = ++playSerial;
        generationById[id] = playToken;
        if (polyphonic) trackGroup(groupId, id);
        var ms = durMsOf(name);
        var pairLoopName = null;
        if (!loop && tagLower === "musicintro" && /_intro$/.test(oneName)) {
          var pairCand = oneName.replace(/_intro$/, "_loop");
          if (DUR.hasOwnProperty(pairCand)) pairLoopName = pairCand;
        }
        var voiceState = activeById[id] = { name: oneName, loop: loop, paused: false };
        if (pairLoopName) {
          var pairLoopId = tagId("musicLOOP");
          pairLoopByIntro[groupId] = pairLoopId;
          generationById[pairLoopId] = ++playSerial;
          activeById[pairLoopId] = { name: pairLoopName, loop: 1, paused: false };
          native("PLAYPAIR|" + id + "|" + pairLoopId + "|" + vol.toFixed(3) + "|" + ms + "|" + oggPath(oneName) + "|" + oggPath(pairLoopName));
          console.log("MUOS_PLAYPAIR intro=" + oneName + " loop=" + pairLoopName + " ms=" + ms + " iid=" + id + " lid=" + pairLoopId);
        } else {
          native("PLAY|" + id + "|" + loop + "|" + vol.toFixed(3) + "|" + oggPath(oneName));
        }
        dlog("MUOS_PLAY name=" + name + " tag=" + tag + " id=" + id + " loop=" + loop + " vol=" + vol.toFixed(2));
        if (!loop) {
          var t = tag;
          var endedToken = musicEpoch;
          voiceState.remaining = ms;
          voiceState.deadline = Date.now() + ms;
          voiceState.finish = function () {
            voiceState.timer = 0;
            if (generationById[id] !== playToken) return;
            if (activeById[id] && activeById[id].name === oneName && !activeById[id].loop) delete activeById[id];
            if (polyphonic) untrackGroup(groupId, id);
            if (pairLoopName)
              dlog("MUOS_PLAYPAIR_ENDED intro=" + oneName + " loop=" + pairLoopName + " token=" + endedToken + " atual=" + musicEpoch);
            // Apenas compatibilidade de eventos C2; a continuidade musical do par ja foi
            // agendada pelo mixer nativo e independe deste timer.
            fireEndedTag(rtRef, pluginRef, t);
          };
          voiceState.timer = setTimeout(voiceState.finish, ms);
        }
      }

      function isGroupPlaying(tag) {
        var groupId = tagId(tag);
        if (activeById[groupId]) return true;
        var voices = groupVoices[groupId];
        if (!voices) return false;
        // Timers normally remove finished voices. Prune defensively before answering C2.
        for (var i = voices.length - 1; i >= 0; --i)
          if (!activeById[voices[i]]) voices.splice(i, 1);
        if (!voices.length) { delete groupVoices[groupId]; return false; }
        return true;
      }
      // C2 event sheets use inverted "Is tag playing" as a retrigger guard. Since the
      // HTML5 audio backend is disabled, the original condition always returned false and
      // emitted mrrun/bikemotor_loop every tick. Mirror the native voice registry instead.
      if (AP.cnds && AP.cnds.IsTagPlaying)
        AP.cnds.IsTagPlaying = function (tag) { return isGroupPlaying(tag); };

      AP.acts.Play = function (file, looping, vol, tag) {
        doPlay(this, (file && file[0]) || "", !!(file && file[1]), looping, vol, tag);
      };
      AP.acts.PlayByName = function (folder, filename, looping, vol, tag) {
        doPlay(this, filename || "", (folder === 1), looping, vol, tag);
      };
      // Variantes espaciais do plugin original também precisam ser desviadas: deixá-las
      // intactas reabre o caminho HTML5/GStreamer que bloqueia o WebProcess. O backend
      // atual não implementa panning, mas preserva arquivo, música/SFX, loop, volume e tag.
      AP.acts.PlayAtPosition = function (file, looping, vol, x, y, angle, inner, outer, outergain, tag) {
        doPlay(this, (file && file[0]) || "", !!(file && file[1]), looping, vol, tag);
      };
      AP.acts.PlayAtObject = function (file, looping, vol, obj, inner, outer, outergain, tag) {
        doPlay(this, (file && file[0]) || "", !!(file && file[1]), looping, vol, tag);
      };
      AP.acts.PlayAtPositionByName = function (folder, filename, looping, vol, x, y, angle, inner, outer, outergain, tag) {
        doPlay(this, filename || "", (folder === 1), looping, vol, tag);
      };
      AP.acts.PlayAtObjectByName = function (folder, filename, looping, vol, obj, inner, outer, outergain, tag) {
        doPlay(this, filename || "", (folder === 1), looping, vol, tag);
      };
      AP.acts.Stop = function (tag) {
        var groupId = tagId(tag);
        eachGroupVoice(groupId, function (voiceId) {
          stopTimer(voiceId);
          invalidate(voiceId);
          delete activeById[voiceId];
          native("STOP|" + voiceId);
        });
        delete groupVoices[groupId];
        stopTimer(groupId);
        invalidate(groupId);
        cancelPairForIntro(groupId);
        delete activeById[groupId];
        native("STOP|" + groupId);
      };
      AP.acts.StopAll = function () {
        ++playSerial;
        for (var voiceId in activeById)
          if (activeById.hasOwnProperty(voiceId)) stopTimer(voiceId);
        activeById = {};
        generationById = {};
        groupVoices = {};
        pairLoopByIntro = {};
        native("STOPALL");
      };
      if (AP.acts.SetVolume) AP.acts.SetVolume = function (tag, vol) {
        var groupId = tagId(tag), v = dbToLinear(vol).toFixed(3);
        eachGroupVoice(groupId, function (voiceId) { native("VOL|" + voiceId + "|" + v); });
        native("VOL|" + groupId + "|" + v);
      };
      if (AP.acts.SetMasterVolume) AP.acts.SetMasterVolume = function (vol) {};
      if (AP.acts.SetPaused) AP.acts.SetPaused = function (tag, state) {
        var groupId = tagId(tag);
        var paused = (state === 0);
        eachGroupVoice(groupId, function (voiceId) { setVoicePaused(voiceId, paused); });
        setVoicePaused(groupId, paused);
        var pairLoopId = pairLoopByIntro[groupId];
        if (typeof pairLoopId !== "undefined") setVoicePaused(pairLoopId, paused);
      };
      if (AP.acts.SetSilent) AP.acts.SetSilent = function (s) {};
      if (AP.acts.SetLooping) AP.acts.SetLooping = function () {};
      if (AP.acts.Preload) AP.acts.Preload = function () {};
      if (AP.acts.PreloadByName) AP.acts.PreloadByName = function () {};

      console.log("MUOS_ACTS_WRAPPED_V12");
      return true;
    } catch (e) {
      try { console.log("MUOS_ACTS_WRAP_ERR " + e); } catch (e2) {}
      return false;
    }
  }

  var tries = 0;
  var installIv = setInterval(function () {
    tries++;
    if (installActWrappers() || tries > 200) clearInterval(installIv);
  }, 50);

  // ---- FIX DE DIMENSAO: watcher reativo de original_width/height ----
  // O jogo infla original p/ 1920x1080 (assume desktop 1080p) -> aspect_scale=360/1080=0.333
  // -> sprites 3x menores. Bloquear SetCanvasSize NAO funciona: o C2 cacheia o ponteiro da
  // acao no load (act.func = GetObjectReference), entao o event sheet chama a func ORIGINAL,
  // nao nosso override. Solucao robusta: WATCHER permanente que restaura 428x240 sempre que
  // original for inflado, e re-dispara setSize p/ recalcular aspect_scale. Independe de timing.
  var NAT_W = 428, NAT_H = 240;
  (function watchOriginalSize() {
    var restores = 0;
    var lowresLogged = false;
    var iv = setInterval(function () {
      try {
        var rt = window.cr_getC2Runtime && window.cr_getC2Runtime();
        if (!rt) return;
        if (typeof rt.original_width !== "number") return;
        var resize = false;
        var wantHigh = window.__muos_lowres === true ? false : true;
        if (rt.wantFullscreenScalingQuality !== wantHigh) {
          rt.wantFullscreenScalingQuality = wantHigh;
          resize = true;
          if (!lowresLogged) {
            lowresLogged = true;
            console.log("MUOS_RENDER_MODE " + (wantHigh ? "high" : "low") +
              " target=" + NAT_W + "x" + NAT_H);
          }
        }
        if (rt.original_width !== NAT_W || rt.original_height !== NAT_H) {
          var was = rt.original_width + "x" + rt.original_height;
          rt.original_width = NAT_W;
          rt.original_height = NAT_H;
          rt.parallax_x_origin = NAT_W / 2;
          rt.parallax_y_origin = NAT_H / 2;
          resize = true;
          restores++;
          if (restores <= 5 || restores % 60 === 0)
            console.log("MUOS_ORIG_RESTORE #" + restores + " de " + was + " -> " + NAT_W + "x" + NAT_H);
        }
        if (resize) try {
          var ww = rt.lastWindowWidth || window.innerWidth || 640;
          var wh = rt.lastWindowHeight || window.innerHeight || 480;
          rt["setSize"](ww, wh, true);
        } catch (e) {}
      } catch (e) {}
    }, 100); // 10x/s: pega a inflacao logo apos ocorrer, antes de 1 frame visivel
    // permanente: nao limpar (o jogo pode re-inflar a cada troca de layout/cutscene)
  })();

  // Telemetria A/B de baixa frequência, desligada em produção.
  if (window.__muos_perf_probe === true) (function perfProbe() {
    var lastTick = 0, lastTime = Date.now();
    var glReported = false;
    setInterval(function () {
      try {
        var rt = window.cr_getC2Runtime && window.cr_getC2Runtime();
        if (!rt) return;
        // ---- Reporte UNICO de modo de render (WebGL vs Canvas2D) + GL_RENDERER ----
        // No Construct 2, rt.gl e o contexto WebGL quando o projeto roda em modo GL;
        // se for null/undefined o runtime esta desenhando via Canvas2D (CPU-bound).
        if (!glReported) {
          try {
            var gl = rt.gl;
            if (gl) {
              var rendu = "?", vend = "?", ver = "?";
              try {
                var dbg = gl.getExtension("WEBGL_debug_renderer_info");
                rendu = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
                vend = dbg ? gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR);
                ver = gl.getParameter(gl.VERSION);
              } catch (e2) {}
              console.log("MUOS_RENDER_MODE=WEBGL renderer=" + rendu + " vendor=" + vend + " version=" + ver +
                " maxtex=" + gl.getParameter(gl.MAX_TEXTURE_SIZE));
              glReported = true;
            } else if (rt.ctx) {
              console.log("MUOS_RENDER_MODE=CANVAS2D (CPU) — WebGL context ausente no runtime C2!");
              glReported = true;
            }
          } catch (eg) {}
        }
        var now = Date.now(), tick = rt.tickcount || 0;
        var tickRate = (tick - lastTick) * 1000 / Math.max(1, now - lastTime);
        lastTick = tick; lastTime = now;
        console.log("MUOS_PERF tickHz=" + tickRate.toFixed(1) +
          " fps=" + (rt.fps || 0) + " cpu=" + (rt.cpuutilisation || 0) +
          " objects=" + (rt.objectcount || 0) +
          " draw=" + rt.draw_width + "x" + rt.draw_height +
          " glmode=" + (rt.gl ? 1 : 0) +
          " layout=" + (rt.running_layout && rt.running_layout.name));
      } catch (e) {}
    }, 2000);
  })();

  // ---- PROBE DE DIMENSOES: interceptar setSize do runtime p/ capturar valores reais ----
  if (DEBUG) (function dimProbe() {
    var installed = false;
    var iv = setInterval(function () {
      try {
        var rt = window.cr_getC2Runtime && window.cr_getC2Runtime();
        if (!rt || installed) return;
        var proto = Object.getPrototypeOf(rt);
        var orig = proto["setSize"] || rt["setSize"];
        if (typeof orig !== "function") return;
        installed = true;
        rt["setSize"] = function (w, h, force) {
          var r = orig.call(this, w, h, force);
          try {
            var cv = this.canvas || {};
            console.log("MUOS_DIM in=" + w + "x" + h +
              " mode=" + this.fullscreen_mode + " dpr=" + this.devicePixelRatio +
              " draw=" + this.draw_width + "x" + this.draw_height +
              " wh=" + this.width + "x" + this.height +
              " css=" + this.cssWidth + "x" + this.cssHeight +
              " canvas=" + (cv.width) + "x" + (cv.height) +
              " win=" + window.innerWidth + "x" + window.innerHeight +
              " domfree=" + this.isDomFree + " aspscale=" + this.aspect_scale);
          } catch (e) {}
          return r;
        };
        console.log("MUOS_DIMPROBE_INSTALLED");
        // POLLER: aspect_scale e' setado no TICK, nao no setSize. amostrar ao vivo.
        var samples = 0, lastSig = "";
        var poll = setInterval(function () {
          try {
            var r2 = window.cr_getC2Runtime && window.cr_getC2Runtime();
            if (!r2) return;
            var lay = r2.running_layout || {};
            var sig = "asp=" + (r2.aspect_scale) +
              " wh=" + r2.width + "x" + r2.height +
              " orig=" + r2.original_width + "x" + r2.original_height +
              " draw=" + r2.draw_width + "x" + r2.draw_height +
              " layScale=" + (lay.scale) +
              " layout=" + (lay.name) +
              " dpr=" + r2.devicePixelRatio;
            if (sig !== lastSig) {
              lastSig = sig;
              console.log("MUOS_TICKDIM " + sig);
            }
            if (++samples > 120) clearInterval(poll);
          } catch (e) {}
        }, 250);
      } catch (e) {}
    }, 100);
    setTimeout(function () { clearInterval(iv); }, 20000);
  })();

  // rede de seguranca: destravar a intro independente do audio
  (function watchdogIntro() {
    var introEnteredAt = 0;
    var iv = setInterval(function () {
      try {
        var rt = window.cr_getC2Runtime && window.cr_getC2Runtime();
        if (!rt || !rt.running_layout) return;
        if (rt.running_layout.name !== "intrologo") {
          if (window.__muos_forced_introend) clearInterval(iv);
          introEnteredAt = 0; return;
        }
        if (!introEnteredAt) introEnteredAt = Date.now();
        if (Date.now() - introEnteredAt > 9000 && !window.__muos_forced_introend) {
          window.__muos_forced_introend = 1;
          var set = 0;
          if (rt.all_global_vars) for (var i = 0; i < rt.all_global_vars.length; i++) {
            var g = rt.all_global_vars[i];
            if (g && g.name === "logoIntroFinished") { g.data = 1; set = 1; }
          }
          console.log("MUOS_FORCE_INTRO_END set=" + set);
        }
      } catch (e) {}
    }, 500);
  })();

  // ============================================================================
  // 12. INTERCEPTAR TODAS AS ROTAS DE SAIDA -> SINALIZAR LAUNCHER
  // ============================================================================
  // O menu "Sair" do Moonrider usa a acao Close do plugin NWjs. Dependendo do
  // ambiente detectado, o C2 chama UMA de varias rotas (window.close, nw.App.quit,
  // navigator.app.exitApp, tizen, CocoonJS...). Interceptamos TODAS e sinalizamos
  // o launcher via muosExit -> g_main_loop_quit(). Log identifica qual disparou.
  (function() {
    function signalQuit(via) {
      try { console.log("MUOS_EXIT_VIA " + via + " -> sinalizando launcher"); } catch (e) {}
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.muosExit) {
          window.webkit.messageHandlers.muosExit.postMessage("QUIT");
          return true;
        }
      } catch (e) {
        try { console.error("MUOS_EXIT error: " + e); } catch (e2) {}
      }
      return false;
    }

    // window.close()
    var originalClose = window.close;
    window.close = function() {
      if (!signalQuit("window.close") && originalClose) {
        try { originalClose.call(window); } catch (e) {}
      }
    };

    // navigator.app.exitApp / navigator.device.exitApp (Cordova-style, ramo do C2)
    try {
      if (!window.navigator) {}
      var nav = window.navigator || {};
      nav.app = nav.app || {};
      nav.app.exitApp = function() { signalQuit("navigator.app.exitApp"); };
      nav.device = nav.device || {};
      nav.device.exitApp = function() { signalQuit("navigator.device.exitApp"); };
    } catch (e) {}

    // nw.App.quit / nw.App.closeAllWindows (NW.js runtime, caso exposto)
    try {
      window.nw = window.nw || {};
      window.nw.App = window.nw.App || {};
      window.nw.App.quit = function() { signalQuit("nw.App.quit"); };
      window.nw.App.closeAllWindows = function() { signalQuit("nw.App.closeAllWindows"); };
    } catch (e) {}

    console.log("MUOS_WINDOW_CLOSE_INTERCEPTOR installed (multi-rota)");
  })();

})();
