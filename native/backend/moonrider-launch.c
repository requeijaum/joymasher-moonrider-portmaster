/*
 * moonrider-launch.c — mini-launcher WPEWebKit para muOS/RG40xx H (fbdev+mali)
 * Substitui o `cog` (que força backend FDO/Wayland). Usa nosso libWPEBackend-mali-fbdev.so
 * via WPE_BACKEND env, cria a view WebKit e carrega a URL. Sem X/Wayland/DRM.
 *
 * Build (docker arm64): gcc moonrider-launch.c -o moonrider-launch \
 *   $(pkg-config --cflags --libs wpe-webkit-1.1 glib-2.0)
 */
#include <wpe/webkit.h>
#include <glib.h>
#include <glib-unix.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include "evdev_gamepad.h"
#include "exit_combo.h"
#include "input_mailbox.h"
#include "muos_audio_mixer.h"

static gboolean audio_engine_enabled = TRUE;

/* Handler das mensagens de audio vindas do shim JS (window.webkit.messageHandlers.muosAudio).
 * Formato pipe-delimitado (simples, sem JSON parser em C):
 *   PLAY|<id>|<loop 0/1>|<vol 0..1>|<path-absoluto>
 *   PLAYPAIR|<intro_id>|<loop_id>|<vol>|<intro_ms>|<intro_path>|<loop_path>
 *   STOP|<id>
 *   VOL|<id>|<vol>
 *   PAUSE|<id>|<0/1>
 *   STOPALL
 * O <path> vem por ultimo pois pode conter qualquer char menos '|' (paths do jogo nao tem).
 */
static void on_audio_message(WebKitUserContentManager *ucm,
                             WebKitJavascriptResult *res, gpointer data) {
    (void)ucm; (void)data;
    JSCValue *val = webkit_javascript_result_get_js_value(res);
    char *msg = jsc_value_to_string(val);
    if (!msg) return;

    char *save = NULL;
    char *cmd = strtok_r(msg, "|", &save);
    if (!cmd) { g_free(msg); return; }

    if (!audio_engine_enabled) {
        static guint64 dropped = 0;
        ++dropped;
        if (dropped <= 8 || (dropped % 100) == 0)
            fprintf(stderr, "[audio-ab] dropped cmd=%s total=%llu\n",
                    cmd, (unsigned long long)dropped);
        g_free(msg);
        return;
    }

    if (strcmp(cmd, "PLAY") == 0) {
        char *sid  = strtok_r(NULL, "|", &save);
        char *slp  = strtok_r(NULL, "|", &save);
        char *svol = strtok_r(NULL, "|", &save);
        char *path = strtok_r(NULL, "",  &save); /* resto = path (pode ter espacos) */
        if (sid && slp && svol && path) {
            int id = atoi(sid), loop = atoi(slp); float vol = (float)atof(svol);
            muos_mixer_play(id, path, loop, vol);
        }
    } else if (strcmp(cmd, "PLAYPAIR") == 0) {
        char *siid = strtok_r(NULL, "|", &save);
        char *slid = strtok_r(NULL, "|", &save);
        char *svol = strtok_r(NULL, "|", &save);
        char *sms  = strtok_r(NULL, "|", &save);
        char *ipath = strtok_r(NULL, "|", &save);
        char *lpath = strtok_r(NULL, "", &save);
        if (siid && slid && svol && sms && ipath && lpath) {
            muos_mixer_play_pair(atoi(siid), atoi(slid), ipath, lpath,
                                 (unsigned int)strtoul(sms, NULL, 10), (float)atof(svol));
        }
    } else if (strcmp(cmd, "STOP") == 0) {
        char *sid = strtok_r(NULL, "|", &save);
        if (sid) muos_mixer_stop(atoi(sid));
    } else if (strcmp(cmd, "VOL") == 0) {
        char *sid  = strtok_r(NULL, "|", &save);
        char *svol = strtok_r(NULL, "|", &save);
        if (sid && svol) muos_mixer_volume(atoi(sid), (float)atof(svol));
    } else if (strcmp(cmd, "PAUSE") == 0) {
        char *sid = strtok_r(NULL, "|", &save);
        char *spaused = strtok_r(NULL, "|", &save);
        if (sid && spaused) muos_mixer_pause(atoi(sid), atoi(spaused) != 0);
    } else if (strcmp(cmd, "STOPALL") == 0) {
        muos_mixer_stop_all();
    }
    g_free(msg);
}

/* limpeza periodica de vozes SFX terminadas (libera slots). */
static gboolean audio_reap_tick(gpointer d) { (void)d; muos_mixer_reap(); return G_SOURCE_CONTINUE; }

/* Main loop global p/ saida limpa via sinal (atalho do muOS manda SIGTERM). */
static GMainLoop *g_loop = NULL;
static gboolean on_term_signal(gpointer data) {
    (void)data;
    if (g_loop) g_main_loop_quit(g_loop);
    return G_SOURCE_REMOVE;
}

/* Handler de mensagens de window.close() vindas do shim JS.
 * O Construct 2 chama window.close() quando o jogador clica em "Sair" no menu.
 * Interceptamos via window.webkit.messageHandlers.muosExit.postMessage("QUIT"). */
static void on_exit_message(WebKitUserContentManager *ucm,
                            WebKitJavascriptResult *res, gpointer data) {
    (void)ucm; (void)res; (void)data;
    fprintf(stderr, "[launch] muosExit recebido (window.close), encerrando...\n");
    if (g_loop) g_main_loop_quit(g_loop);
}

/* Latest-state mailbox: never queue an unbounded history of run_javascript()
 * calls. One snapshot may be in flight and one newer snapshot may be pending;
 * further evdev changes overwrite the pending slot. */
static muos_input_mailbox gamepad_mailbox;
static uint64_t gamepad_coalesced_total = 0;

static gboolean diagnostics_heartbeat(gpointer data) {
    (void)data;
    static guint64 heartbeat = 0;
    muos_audio_worker_stats audio = {0};
    guint64 worker_age_ms = 0;
    if (audio_engine_enabled) {
        muos_mixer_get_stats(&audio);
        if (audio.heartbeat_ns) {
            guint64 now_ns = (guint64)g_get_monotonic_time() * 1000U;
            if (now_ns > audio.heartbeat_ns)
                worker_age_ms = (now_ns - audio.heartbeat_ns) / 1000000U;
        }
    }
    fprintf(stderr,
            "[heartbeat] mainloop=%llu coalesced=%llu audio_engine=%s "
            "worker_state=%d op=%d age_ms=%llu q=%zu hwm=%zu processed=%llu "
            "audio_coalesced=%llu dropped=%llu breaker=%d stalls=%llu\n",
            (unsigned long long)++heartbeat,
            (unsigned long long)gamepad_coalesced_total,
            audio_engine_enabled ? "on" : "off",
            (int)audio.state, audio.current_operation,
            (unsigned long long)worker_age_ms,
            audio.queue_depth, audio.queue_high_watermark,
            (unsigned long long)audio.processed,
            (unsigned long long)audio.coalesced,
            (unsigned long long)audio.dropped,
            audio.breaker_open,
            (unsigned long long)audio.stall_events);
    return G_SOURCE_CONTINUE;
}

typedef struct {
    muos_input_snapshot snapshot;
    gint64 queued_us;
} gamepad_js_trace;

static void gamepad_send_latest(WebKitWebView *view);

static void gamepad_js_done(GObject *src, GAsyncResult *res, gpointer data) {
    gamepad_js_trace *trace = (gamepad_js_trace *)data;
    GError *err = NULL;
    WebKitJavascriptResult *result = webkit_web_view_run_javascript_finish(
        WEBKIT_WEB_VIEW(src), res, &err);
    gint64 latency_us = g_get_monotonic_time() - trace->queued_us;

    if (err || latency_us >= 100000) {
        fprintf(stderr,
                "[pad-latest] ACK seq=%llu latency_us=%lld status=%s coalesced=%llu%s%s\n",
                (unsigned long long)trace->snapshot.seq,
                (long long)latency_us,
                result ? "ok" : "error",
                (unsigned long long)gamepad_coalesced_total,
                err ? " message=" : "", err ? err->message : "");
    }
    if (result) webkit_javascript_result_unref(result);
    if (err) g_error_free(err);
    muos_input_mailbox_complete(&gamepad_mailbox, &trace->snapshot, result != NULL);
    g_free(trace);
    gamepad_send_latest(WEBKIT_WEB_VIEW(src));
}

static void gamepad_send_latest(WebKitWebView *view) {
    muos_input_snapshot snapshot;
    if (!muos_input_mailbox_begin_send(&gamepad_mailbox, &snapshot)) return;

    char js[640];
    snprintf(js, sizeof(js),
        "if(window.__muos_pushGamepad)__muos_pushGamepad("
        "[%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f],"
        "[%.3f,%.3f,%.3f,%.3f],"
        "[%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d],%llu);",
        snapshot.buttons[0],snapshot.buttons[1],snapshot.buttons[2],snapshot.buttons[3],
        snapshot.buttons[4],snapshot.buttons[5],snapshot.buttons[6],snapshot.buttons[7],
        snapshot.buttons[8],snapshot.buttons[9],snapshot.buttons[10],snapshot.buttons[11],
        snapshot.buttons[12],snapshot.buttons[13],snapshot.buttons[14],snapshot.buttons[15],
        snapshot.buttons[16], snapshot.axes[0],snapshot.axes[1],snapshot.axes[2],
        snapshot.axes[3],
        snapshot.press_edges[0],snapshot.press_edges[1],snapshot.press_edges[2],
        snapshot.press_edges[3],snapshot.press_edges[4],snapshot.press_edges[5],
        snapshot.press_edges[6],snapshot.press_edges[7],snapshot.press_edges[8],
        snapshot.press_edges[9],snapshot.press_edges[10],snapshot.press_edges[11],
        snapshot.press_edges[12],snapshot.press_edges[13],snapshot.press_edges[14],
        snapshot.press_edges[15],snapshot.press_edges[16],
        (unsigned long long)snapshot.seq);

    gamepad_js_trace *trace = g_new(gamepad_js_trace, 1);
    trace->snapshot = snapshot;
    trace->queued_us = g_get_monotonic_time();
    webkit_web_view_run_javascript(view, js, NULL, gamepad_js_done, trace);
}

/* Samples the physical state on the UIProcess main loop. Exit remains native
 * and therefore independent from WebProcess congestion. */
static gboolean gamepad_pulse(gpointer data) {
    WebKitWebView *view = WEBKIT_WEB_VIEW(data);
    float btn[MUOS_NBTN], ax[MUOS_NAXES];
    int dirty = muos_gamepad_snapshot(btn, ax);
    {
        /* Saida muOS: pressionar L2(idx6)+R1(idx5), soltar e repetir em ate 2 s.
         * Combo trocado de MODE+START (nunca disparava: o hardware do RG40XX
         * reporta os botoes do usuario como BTN_TL2/BTN_TR, nao BTN_MODE/BTN_START,
         * confirmado por captura evtest 2026-07-14). Deteccao por borda dupla;
         * segurar uma vez nunca conta como duas. */
        static muos_exit_combo_state exit_combo = {0};
        if (muos_exit_combo_update(&exit_combo,
                                   btn[6] >= 0.5f, btn[5] >= 0.5f,
                                   g_get_monotonic_time())) {
            fprintf(stderr, "[launch] L2+R1 x2 confirmado -> saindo\n");
            if (g_loop) g_main_loop_quit(g_loop);
            return G_SOURCE_REMOVE;
        }
    }
    if (dirty) {
        if (gamepad_mailbox.in_flight && gamepad_mailbox.pending)
            gamepad_coalesced_total++;
        muos_input_mailbox_update(&gamepad_mailbox, btn, ax);
        gamepad_send_latest(view);
    }
    return G_SOURCE_CONTINUE;
}


static void js_probe_done(GObject *src, GAsyncResult *res, gpointer data) {
    GError *err = NULL;
    WebKitJavascriptResult *r = webkit_web_view_run_javascript_finish(WEBKIT_WEB_VIEW(src), res, &err);
    if (!r) {
        fprintf(stderr, "[launch] JS_PROBE_ERROR %s\n", err ? err->message : "?");
        if (err) g_error_free(err);
        return;
    }
    JSCValue *v = webkit_javascript_result_get_js_value(r);
    char *s = jsc_value_to_string(v);
    fprintf(stderr, "[launch] JS_PROBE_RESULT %s\n", s ? s : "(null)");
    g_free(s);
    webkit_javascript_result_unref(r);
}

static int pulse_inflight = 0;
static int pulse_started = 0;

static void js_pulse_done(GObject *src, GAsyncResult *res, gpointer data) {
    GError *err = NULL;
    WebKitJavascriptResult *r = webkit_web_view_run_javascript_finish(WEBKIT_WEB_VIEW(src), res, &err);
    pulse_inflight = 0;
    if (!r) { if (err) g_error_free(err); return; }
    webkit_javascript_result_unref(r);
}

static gboolean run_js_chunk_pulse(gpointer data) {
    static int pulse_count = 0;
    static int skipped_inflight = 0;
    WebKitWebView *view = WEBKIT_WEB_VIEW(data);
    pulse_count++;
    if (pulse_inflight) {
        skipped_inflight++;
        return pulse_count > 80 ? G_SOURCE_REMOVE : G_SOURCE_CONTINUE;
    }
    pulse_inflight = 1;
    /* CONFIG test86 + rota3 (anti-deadlock): suprime o draw durante o empurrao do pulse.
     * O deadlock vinha do drawGL()/swapbuffers do WebGL travando no compositor fbdev
     * (3o lote de tick bloqueava). Setando rt.redraw=false ANTES do tick, o bloco de
     * draw (c2runtime linha ~5154) e pulado, o tick avanca sem tocar no GL, e o loop
     * INTERNO do C2 assume (como no test86: tick 26->199 sozinho). So empurra ate tick
     * ~40; depois disso o pulse para de forcar (deixa o loop interno + SYNTH agirem). */
    const char *script =
        "(function(){try{"
        "var rt=window.cr_getC2Runtime&&window.cr_getC2Runtime();"
        "if(rt&&rt.running_layout&&!rt.isSuspended){"
        " var pushing=(rt.tickcount||0)<40;"                     /* so empurra ate tick 40 */
        " if(pushing){ var n=0; for(var i=0;i<5;i++){ rt.redraw=false; rt.tick(false); n++; } window.__muos_chunk_pulse=(window.__muos_chunk_pulse||0)+n; }"
        " if((window.__muos_chunk_pulse||0)<=40) console.log('MUOS_CHUNK_PULSE', window.__muos_chunk_pulse||0, 'layout='+(rt.running_layout&&rt.running_layout.name), 'tick='+rt.tickcount, 'push='+pushing);"
        " return (rt.tickcount||0)>60 ? 'done' : ('chunk '+(window.__muos_chunk_pulse||0)+' tick='+rt.tickcount+' push='+pushing);"
        "} window.__muos_no_runtime=(window.__muos_no_runtime||0)+1; if(window.__muos_no_runtime<=5||window.__muos_no_runtime%50===0) console.log('MUOS_CHUNK_NO_RUNTIME', window.__muos_no_runtime); return 'no-runtime';"
        "}catch(e){console.error('MUOS_CHUNK_PULSE_ERR', e&&e.stack||e); return 'err';}})()";
    webkit_web_view_run_javascript(view, script, NULL, js_pulse_done, NULL);
    /* Auto-remove o chunk-pulse depois do kick inicial (~8s = 80 pulsos a 100ms): o rAF
     * nativo do C2 ja assumiu o loop. Elimina o clock concorrente e a contencao
     * UIProcess<->WebProcess por frame no gameplay. O kick (tick<40) tira o C2 da inercia. */
    if (pulse_count > 80) { fprintf(stderr, "[launch] chunk-pulse OFF (rAF assumiu, ~8s)\n"); return G_SOURCE_REMOVE; }
    return G_SOURCE_CONTINUE;
}

static gboolean run_js_probe(gpointer data) {
    WebKitWebView *view = WEBKIT_WEB_VIEW(data);
    const char *script =
        "(function(){"
        "var b=document.body, e=document.documentElement;"
        "var c=b?getComputedStyle(b).backgroundColor:'nobody';"
        "var txt=(b&&b.innerText)||'';"
        "var cv=document.querySelector('canvas');"
        "var gl='nocanvas';"
        "if(cv){try{gl=!!(cv.getContext('webgl')||cv.getContext('experimental-webgl'));}catch(e){gl='ERR:'+e.message;}}"
        "var rt=window.cr_getC2Runtime&&window.cr_getC2Runtime();"
        "var tex='nort';"
        "if(rt&&rt.wait_for_textures){var a=rt.wait_for_textures, ok=0, sample=[]; for(var i=0;i<a.length;i++){var im=a[i]; if(im && im.src && (im.complete||im.loaded)&&!im.c2error) ok++; if(i<8&&im) sample.push((im.cr_src||im.src)+'|c='+im.complete+'|nw='+im.naturalWidth+'|src='+im.src.slice(0,80));} if(a.length && ok===a.length && !rt.running_layout && !window.__muos_forced_go){window.__muos_forced_go=1; try{console.log('MUOS_LAUNCHER_FORCE_GO', 'ok='+ok, 'preloadSounds='+rt.preloadSounds); rt.preloadSounds=false; rt.progress=1; rt.go();}catch(e){console.error('MUOS_LAUNCHER_FORCE_GO_ERR', e&&e.stack||e); try{rt.go_loading_finished();}catch(e2){console.error('MUOS_LAUNCHER_FORCE_FINISH_ERR', e2&&e2.stack||e2);}}} tex='tex='+a.length+' ok='+ok+' progress='+rt.progress+' loading='+rt.loadingprogress+' layout='+(rt.running_layout&&rt.running_layout.name)+' forced='+(window.__muos_forced_go||0)+' sample='+sample.join(';;');}"
        "var pt=(window.__prof0?Math.round(((performance&&performance.now)?performance.now():Date.now())-window.__prof0):-1);"
        "var gv=''; if(rt&&rt.all_global_vars){var want={curMenu:1,loadFinished:1,logoIntroFinished:1,isDEMO:1,gobackToLayout:1}; var arr=[]; for(var gi=0; gi<rt.all_global_vars.length; gi++){var g=rt.all_global_vars[gi]; if(g&&want[g.name]) arr.push(g.name+'='+g.data);} gv=' globals='+arr.join(',');}"
        "return 'T+'+pt+'ms ready='+document.readyState+' size='+innerWidth+'x'+innerHeight+' bg='+c+' text='+txt.slice(0,80)+' canvas='+(cv?cv.width+'x'+cv.height:'none')+' gl='+gl+' '+tex+gv;"
        "})()";
    webkit_web_view_run_javascript(view, script, NULL, js_probe_done, NULL);
    return G_SOURCE_REMOVE;
}

static void schedule_probes(WebKitWebView *view) {
    g_timeout_add(1000, run_js_probe, view);
    g_timeout_add(5000, run_js_probe, view);
    g_timeout_add(15000, run_js_probe, view);
}

static void on_load_changed(WebKitWebView *view, WebKitLoadEvent ev, gpointer data) {
    const char *uri = webkit_web_view_get_uri(view);
    switch (ev) {
        case WEBKIT_LOAD_STARTED:   fprintf(stderr, "[launch] LOAD_STARTED %s\n", uri ? uri : "?"); break;
        case WEBKIT_LOAD_COMMITTED: fprintf(stderr, "[launch] LOAD_COMMITTED %s\n", uri ? uri : "?"); break;
        case WEBKIT_LOAD_FINISHED:
            fprintf(stderr, "[launch] LOAD_FINISHED %s\n", uri ? uri : "?");
            /* Stable PortMaster build: do not run diagnostic JS probes or the
             * early chunk-pulse while Construct is still preloading. On the
             * packaged tree those async run_javascript calls killed the
             * WPEWebProcess around 100/1293 textures. */
            break;
        default: break;
    }
}

static gboolean on_load_failed(WebKitWebView *view, WebKitLoadEvent ev,
                               const char *uri, GError *error, gpointer data) {
    fprintf(stderr, "[launch] LOAD_FAILED %s: %s\n", uri, error ? error->message : "?");
    return FALSE;
}

/* mensagens de console JS do jogo → stdout via setting abaixo */

static char* file_uri_to_path(const char *uri) {
    if (!g_str_has_prefix(uri, "file://")) return NULL;
    return g_strdup(uri + 7);
}

static char* file_uri_base(const char *uri) {
    char *slash = g_strrstr(uri, "/");
    if (!slash) return g_strdup(uri);
    return g_strndup(uri, slash - uri + 1);
}

static gboolean add_user_script_file(WebKitUserContentManager *ucm,
                                     const char *path) {
    gchar *source = NULL;
    gsize length = 0;
    GError *error = NULL;
    if (!g_file_get_contents(path, &source, &length, &error)) {
        fprintf(stderr, "[launch] ERRO: shim ausente/ilegível %s: %s\n",
                path, error ? error->message : "?");
        if (error) g_error_free(error);
        return FALSE;
    }
    WebKitUserScript *script = webkit_user_script_new(
        source,
        WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        NULL,
        NULL);
    webkit_user_content_manager_add_script(ucm, script);
    webkit_user_script_unref(script);
    fprintf(stderr, "[launch] shim document-start carregado: %s (%zu bytes)\n",
            path, (size_t)length);
    g_free(source);
    return TRUE;
}

static gboolean add_frameskip_override(WebKitUserContentManager *ucm) {
    const char *value = getenv("MOONRIDER_FRAMESKIP");
    if (!value || !*value) return TRUE;

    char *end = NULL;
    long frameskip = strtol(value, &end, 10);
    if (!end || *end != '\0' || frameskip < 0 || frameskip > 3) {
        fprintf(stderr,
                "[launch] AVISO: MOONRIDER_FRAMESKIP invalido '%s' (use 0..3)\n",
                value);
        return TRUE;
    }

    gchar *source = g_strdup_printf(
        "window.MOONRIDER_FRAMESKIP_OVERRIDE=%ld;", frameskip);
    WebKitUserScript *script = webkit_user_script_new(
        source,
        WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        NULL,
        NULL);
    webkit_user_content_manager_add_script(ucm, script);
    webkit_user_script_unref(script);
    g_free(source);
    fprintf(stderr, "[launch] frameskip fixo configurado: %ld\n", frameskip);
    return TRUE;
}

int main(int argc, char *argv[]) {
    const char *url = (argc > 1) ? argv[1] : "file:///mnt/mmc/wpe-test/smoke.html";
    audio_engine_enabled = getenv("MOONRIDER_DISABLE_AUDIO") == NULL;
    fprintf(stderr, "[launch] iniciando; url=%s\n", url);
    fprintf(stderr, "[launch] WPE_BACKEND=%s\n", getenv("WPE_BACKEND") ? getenv("WPE_BACKEND") : "(nao setado!)");

    /* cria o wpe_view_backend via loader do WPE_BACKEND (nosso mali-fbdev) */
    struct wpe_view_backend *wpe_backend = wpe_view_backend_create();
    if (!wpe_backend) {
        fprintf(stderr, "[launch] ERRO: wpe_view_backend_create() retornou NULL\n");
        return 2;
    }
    fprintf(stderr, "[launch] wpe_view_backend criado OK\n");

    /* embrulha no WebKitWebViewBackend */
    WebKitWebViewBackend *view_backend =
        webkit_web_view_backend_new(wpe_backend, NULL, NULL);

    /* UserContentManager: canal JS->nativo p/ o mixer de audio (contorna o
     * GStreamer que trava no sandbox). O shim JS faz:
     *   window.webkit.messageHandlers.muosAudio.postMessage("PLAY|id|loop|vol|path") */
    WebKitUserContentManager *ucm = webkit_user_content_manager_new();
    webkit_user_content_manager_register_script_message_handler(ucm, "muosAudio");
    g_signal_connect(ucm, "script-message-received::muosAudio",
                     G_CALLBACK(on_audio_message), NULL);

    /* Canal JS->nativo para window.close() (botão "Sair" do menu). O shim JS faz:
     *   window.webkit.messageHandlers.muosExit.postMessage("QUIT") */
    webkit_user_content_manager_register_script_message_handler(ucm, "muosExit");
    g_signal_connect(ucm, "script-message-received::muosExit",
                     G_CALLBACK(on_exit_message), NULL);

    /* The BYO package receives raw game assets only after installation. Inject
     * the maintained layer from the port itself instead of requiring Python or
     * rewriting the user's index.html on the handheld. */
    const char *shim_dir = getenv("MOONRIDER_SHIM_DIR");
    if (!shim_dir || !*shim_dir) {
        fprintf(stderr, "[launch] ERRO: MOONRIDER_SHIM_DIR não definido\n");
        return 3;
    }
    char *gamepad_shim = g_build_filename(shim_dir, "muos_gamepad_shim.js", NULL);
    char *audio_shim = g_build_filename(shim_dir, "muos_audio_ghost.js", NULL);
    char *frameskip_shim = g_build_filename(shim_dir, "muos_frameskip.js", NULL);
    gboolean shims_ok = add_user_script_file(ucm, audio_shim) &&
                        add_user_script_file(ucm, gamepad_shim) &&
                        add_frameskip_override(ucm) &&
                        add_user_script_file(ucm, frameskip_shim);
    g_free(gamepad_shim);
    g_free(audio_shim);
    g_free(frameskip_shim);
    if (!shims_ok) return 3;

    /* cria a web view COM o backend e o user content manager */
    WebKitWebView *view = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,
        "backend", view_backend,
        "user-content-manager", ucm,
        NULL));
    fprintf(stderr, "[launch] WebKitWebView criada OK (com muosAudio handler)\n");

    /* A/B real: não inicializa miniaudio, libvorbis, ALSA/PipeWire nem reap timer.
     * O Audio Ghost continua oferecendo a API esperada pelo Construct, mas suas
     * mensagens são descartadas no começo de on_audio_message(). */
    if (!audio_engine_enabled) {
        fprintf(stderr, "[audio-ab] engine disabled; mixer init/reap/play bypassed\n");
    } else if (muos_mixer_init() != 0) {
        fprintf(stderr, "[launch] AVISO: mixer de audio nao iniciou (jogo seguira mudo)\n");
    } else {
        g_timeout_add(1000, audio_reap_tick, NULL); /* libera slots de SFX terminados */
    }

    /* settings: habilitar WebGL, aceleração, permitir file:// acessar recursos */
    WebKitSettings *s = webkit_web_view_get_settings(view);
    webkit_settings_set_enable_webgl(s, TRUE);
    /* WebKit 1.1 no muOS não expõe a API de policy de aceleração. O backend
     * EGL já é selecionado por WPE_BACKEND + WEBKIT_FORCE_COMPOSITING_MODE. */
    webkit_settings_set_allow_file_access_from_file_urls(s, TRUE);
    webkit_settings_set_allow_universal_access_from_file_urls(s, TRUE);
    /* Console JS -> stdout -> log em SD custa CPU/I/O. Reativar só em diagnóstico. */
    webkit_settings_set_enable_write_console_messages_to_stdout(
        s, getenv("MUOS_DEBUG") != NULL);

    g_signal_connect(view, "load-changed", G_CALLBACK(on_load_changed), NULL);
    g_signal_connect(view, "load-failed",  G_CALLBACK(on_load_failed),  NULL);

    /* fundo preto e carrega. Em muOS faltam MIME DBs; file:// .html cai como text/plain.
     * Para HTML local, ler o arquivo e usar load_html(base_uri) para forçar MIME text/html
     * mantendo caminhos relativos para assets do Construct. Este é o caminho dos snapshots
     * VITORIA/DIMFIX funcionais. */
    WebKitColor bg = { 0, 0, 0, 1 };
    webkit_web_view_set_background_color(view, &bg);
    char *path = file_uri_to_path(url);
    if (path && g_str_has_suffix(path, ".html")) {
        gchar *contents = NULL; gsize len = 0; GError *err = NULL;
        if (g_file_get_contents(path, &contents, &len, &err)) {
            char *base = file_uri_base(url);
            fprintf(stderr, "[launch] load_html local path=%s len=%zu base=%s\n", path, (size_t)len, base);
            webkit_web_view_load_html(view, contents, base);
            g_free(base);
            g_free(contents);
        } else {
            fprintf(stderr, "[launch] load_html failed for %s: %s; falling back load_uri\n", path, err ? err->message : "?");
            if (err) g_error_free(err);
            webkit_web_view_load_uri(view, url);
        }
    } else {
        webkit_web_view_load_uri(view, url);
    }
    g_free(path);
    fprintf(stderr, "[launch] load chamado; entrando no main loop\n");

    /* 60 Hz acompanha o tick-alvo; 120 Hz só duplicava wakeups/mutex sem criar frames. */
    muos_input_mailbox_init(&gamepad_mailbox);
    muos_gamepad_start();
    g_timeout_add(16, gamepad_pulse, view);
    if (getenv("MUOS_DIAGNOSTICS"))
        g_timeout_add(1000, diagnostics_heartbeat, NULL);
    fprintf(stderr, "[launch] gamepad evdev iniciado (push 60Hz)\n");

    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    g_loop = loop;
    /* g_unix_signal_add converte sinais em eventos do GMainLoop. Diferente de
     * signal()+g_idle_add no handler, não chama API não-async-safe no contexto do sinal. */
    g_unix_signal_add(SIGTERM, on_term_signal, NULL);
    g_unix_signal_add(SIGINT,  on_term_signal, NULL);
    g_main_loop_run(loop);
    fprintf(stderr, "[launch] main loop encerrado; saindo limpo\n");
    if (audio_engine_enabled) muos_mixer_shutdown();
    muos_gamepad_stop();
    return 0;
}
