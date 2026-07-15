/*
 * muos_audio_mixer.c — mixer de audio nativo (fora do sandbox do WebProcess)
 *
 * MOTIVO: o pipeline GStreamer DENTRO do WebProcess trava ao decodificar .ogg
 * (autoaudiosink->alsasink->default->pipewire congela no sandbox). Mas ogg123/ffplay
 * FORA do sandbox tocam o mesmo .ogg sem travar. Este mixer roda no processo do
 * launcher (nao-sandboxed) e recebe comandos do JS via message handler 'muosAudio'.
 *
 * Usa miniaudio (ma_engine) + backend libvorbis (libvorbisfile do device, 3.3.8).
 * - ma_engine mixa N vozes automaticamente (musica de fundo + varios SFX simultaneos).
 * - SFX: MA_SOUND_FLAG_DECODE (decodifica pra RAM 1x, toca instantaneo — agil).
 * - Musica (loop): MA_SOUND_FLAG_STREAM (nao carrega 118MB de ogg na RAM).
 * - Backend ALSA aberto via dlopen(libasound) pelo proprio miniaudio -> caminho
 *   "default" = pipewire, o mesmo que ogg123 provou funcionar.
 *
 * API chamada exclusivamente pela thread do GLib main loop. O estado de vozes
 * não precisa de mutex externo; miniaudio sincroniza internamente com o callback.
 *   muos_mixer_init()                         -> 0 ok
 *   muos_mixer_play(id, path, loop, volume)   toca/reinicia a voz 'id'
 *   muos_mixer_stop(id)                       para a voz 'id'
 *   muos_mixer_volume(id, v)                  ajusta volume (0..1) da voz 'id'
 *   muos_mixer_stop_all()
 *   muos_mixer_shutdown()
 *
 * 'id' = inteiro estavel atribuido pelo shim JS a cada elemento <audio>.
 */
#define MINIAUDIO_IMPLEMENTATION
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_ALSA
#define MA_NO_PULSEAUDIO
#define MA_NO_JACK
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

/* backend libvorbis (usa libvorbisfile do device) */
#define MA_HAS_VORBIS
#include "miniaudio_libvorbis.h"
#include "miniaudio_libvorbis.c"

#include <stdio.h>
#include <string.h>


#define MUOS_MAX_VOICES 64

typedef struct {
    int      id;         /* id logico vindo do JS; -1 = slot livre */
    ma_sound snd;
    int      active;     /* 1 se ma_sound foi inicializado */
    int      loop;
    int      paused;
    ma_uint64 scheduled_start;
    ma_uint64 paused_at;
} muos_voice;

static struct {
    int                 inited;
    ma_engine           engine;
    ma_resource_manager rm;
    muos_voice          voices[MUOS_MAX_VOICES];
} G = { 0 };

static ma_decoding_backend_vtable* g_vorbis_vtables[] = {
    /* preenchido em init a partir de ma_decoding_backend_libvorbis */
    NULL
};

static muos_voice* find_voice(int id) {
    for (int i = 0; i < MUOS_MAX_VOICES; i++)
        if (G.voices[i].active && G.voices[i].id == id) return &G.voices[i];
    return NULL;
}
static muos_voice* alloc_voice(int id) {
    for (int i = 0; i < MUOS_MAX_VOICES; i++)
        if (!G.voices[i].active) { G.voices[i].id = id; return &G.voices[i]; }
    return NULL;
}

static void free_voice(muos_voice* v) {
    if (v->active) { ma_sound_uninit(&v->snd); v->active = 0; v->id = -1; }
}

static void reap_finished_voices(void) {
    for (int i = 0; i < MUOS_MAX_VOICES; i++) {
        muos_voice* v = &G.voices[i];
        if (v->active && !v->loop && !v->paused &&
            !ma_sound_is_playing(&v->snd) && ma_sound_at_end(&v->snd))
            free_voice(v);
    }
}

static int voice_slots_available_for_pair(int intro_id, int loop_id) {
    if (intro_id == loop_id) return 0;
    int n = 0;
    for (int i = 0; i < MUOS_MAX_VOICES; i++) {
        muos_voice* v = &G.voices[i];
        if (!v->active || v->id == intro_id || v->id == loop_id) n++;
    }
    return n;
}

/* start_at=0 inicia agora; caso contrario agenda no relogio global do engine. */
static int init_voice(int id, const char* path, int loop, float volume,
                      ma_uint64 start_at) {
    muos_voice* v = find_voice(id);
    if (v) free_voice(v);
    v = alloc_voice(id);
    if (!v) {
        fprintf(stderr, "[mixer] sem slots p/ id=%d\n", id);
        return -1;
    }
    ma_uint32 flags = loop ? MA_SOUND_FLAG_STREAM : MA_SOUND_FLAG_DECODE;
    flags |= MA_SOUND_FLAG_ASYNC;
    ma_result r = ma_sound_init_from_file(&G.engine, path, flags, NULL, NULL, &v->snd);
    if (r != MA_SUCCESS) {
        v->id = -1;
        fprintf(stderr, "[mixer] init_from_file FALHOU id=%d r=%d path=%s\n", id, r, path);
        return -1;
    }
    v->active = 1;
    v->loop = loop;
    v->paused = 0;
    v->scheduled_start = start_at;
    v->paused_at = 0;
    ma_sound_set_looping(&v->snd, loop ? MA_TRUE : MA_FALSE);
    ma_sound_set_volume(&v->snd, volume < 0 ? 1.0f : volume);
    if (start_at) ma_sound_set_start_time_in_pcm_frames(&v->snd, start_at);
    ma_sound_start(&v->snd);
    return 0;
}

int muos_mixer_init(void) {
    if (G.inited) return 0;
    memset(&G, 0, sizeof(G));
    for (int i = 0; i < MUOS_MAX_VOICES; i++) { G.voices[i].id = -1; }

    g_vorbis_vtables[0] = ma_decoding_backend_libvorbis; /* symbol de ma_libvorbis.c */

    /* resource manager com backend vorbis custom.
     * FIXA formato 2ch/44100 (taxa nativa do card0 audiocodec): o ogg da intro e' MONO 44.1k;
     * sem fixar, o miniaudio pode negociar mal sob dlopen-ALSA/fbdev e interpretar o mono como
     * estereo -> toca em METADE do tempo ("muito rapido"/agudo). Fixando, ele converte mono->2ch
     * e mantem 44100 = pitch e duracao corretos. */
    ma_resource_manager_config rmc = ma_resource_manager_config_init();
    rmc.ppCustomDecodingBackendVTables = g_vorbis_vtables;
    rmc.customDecodingBackendCount     = 1;
    rmc.pCustomDecodingBackendUserData = NULL;
    rmc.decodedFormat     = ma_format_f32;
    rmc.decodedChannels   = 2;
    rmc.decodedSampleRate = 44100;
    if (ma_resource_manager_init(&rmc, &G.rm) != MA_SUCCESS) {
        fprintf(stderr, "[mixer] resource_manager_init FALHOU\n");
        return -1;
    }

    ma_engine_config ec = ma_engine_config_init();
    ec.pResourceManager = &G.rm;
    ec.channels         = 2;
    ec.sampleRate       = 44100;
    if (ma_engine_init(&ec, &G.engine) != MA_SUCCESS) {
        fprintf(stderr, "[mixer] engine_init FALHOU\n");
        ma_resource_manager_uninit(&G.rm);
        return -1;
    }
    G.inited = 1;
    fprintf(stderr, "[mixer] init OK (ma_engine + libvorbis, ALSA/default->pipewire)\n");
    return 0;
}

/* toca/reinicia a voz 'id'. loop=1 -> streaming (musica); loop=0 -> decode RAM (SFX). */
int muos_mixer_play(int id, const char* path, int loop, float volume) {
    if (!G.inited || !path || !*path) return -1;
    reap_finished_voices();
    return init_voice(id, path, loop, volume, 0);
}

/* Inicia intro agora e pre-agenda o loop no MESMO relogio de audio.
 * Evita setTimeout JS, gap de abertura tardia do OGG e loops que nunca iniciam sob carga. */
int muos_mixer_play_pair(int intro_id, int loop_id, const char* intro_path,
                         const char* loop_path, unsigned int intro_ms, float volume) {
    if (!G.inited || !intro_path || !*intro_path || !loop_path || !*loop_path || intro_ms == 0)
        return -1;
    reap_finished_voices();
    if (voice_slots_available_for_pair(intro_id, loop_id) < 2) {
        fprintf(stderr, "[mixer] PLAYPAIR sem dois slots livres intro=%d loop=%d\n", intro_id, loop_id);
        return -2;
    }
    ma_uint64 now = ma_engine_get_time_in_pcm_frames(&G.engine);
    ma_uint64 at = now + ((ma_uint64)ma_engine_get_sample_rate(&G.engine) * intro_ms) / 1000;
    int ri = init_voice(intro_id, intro_path, 0, volume, 0);
    if (ri != 0) {
        fprintf(stderr, "[mixer] PLAYPAIR intro falhou intro=%d loop=%d ri=%d\n",
                intro_id, loop_id, ri);
        return -3;
    }
    int rl = init_voice(loop_id, loop_path, 1, volume, at);
    if (rl != 0) {
        muos_voice* intro = find_voice(intro_id);
        if (intro) free_voice(intro);
    }
    fprintf(stderr, "[mixer] PLAYPAIR intro=%d loop=%d ms=%u at=%llu ri=%d rl=%d\n",
            intro_id, loop_id, intro_ms, (unsigned long long)at, ri, rl);
    return (ri == 0 && rl == 0) ? 0 : -1;
}

int muos_mixer_stop(int id) {
    if (!G.inited) return -1;
    muos_voice* v = find_voice(id);
    if (v) free_voice(v);
    return 0;
}

int muos_mixer_volume(int id, float v) {
    if (!G.inited) return -1;
    muos_voice* vc = find_voice(id);
    if (vc && vc->active) ma_sound_set_volume(&vc->snd, v);
    return 0;
}

int muos_mixer_pause(int id, int paused) {
    if (!G.inited) return -1;
    muos_voice* v = find_voice(id);
    if (!v || !v->active) return 0;
    ma_uint64 now = ma_engine_get_time_in_pcm_frames(&G.engine);
    if (paused && !v->paused) {
        v->paused_at = now;
        v->paused = 1;
        ma_sound_stop(&v->snd);
    } else if (!paused && v->paused) {
        /* Se a voz ainda tinha inicio futuro (loop de PLAYPAIR), empurre o
         * agendamento pelo tempo em pausa para nao sobrepor a intro retomada. */
        if (v->scheduled_start > v->paused_at) {
            v->scheduled_start += now - v->paused_at;
            ma_sound_set_start_time_in_pcm_frames(&v->snd, v->scheduled_start);
        }
        v->paused = 0;
        v->paused_at = 0;
        ma_sound_start(&v->snd);
    }
    return 0;
}

void muos_mixer_stop_all(void) {
    if (!G.inited) return;
    for (int i = 0; i < MUOS_MAX_VOICES; i++) free_voice(&G.voices[i]);
}

/* limpeza periodica: libera vozes nao-loop que ja terminaram (evita vazar slots). */
void muos_mixer_reap(void) {
    if (!G.inited) return;
    reap_finished_voices();
}

void muos_mixer_shutdown(void) {
    if (!G.inited) return;
    muos_mixer_stop_all();
    ma_engine_uninit(&G.engine);
    ma_resource_manager_uninit(&G.rm);

    G.inited = 0;
}
