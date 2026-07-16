/* miniaudio backend; called only by the dedicated audio-owner thread. */
#define MINIAUDIO_IMPLEMENTATION
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_ALSA
#define MA_NO_PULSEAUDIO
#define MA_NO_JACK
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#define MA_HAS_VORBIS
#include "miniaudio_libvorbis.h"
#include "miniaudio_libvorbis.c"

#include "miniaudio_backend.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define MUOS_MAX_VOICES 128
#define MUOS_RETIRE_GRACE_NS UINT64_C(150000000)

typedef struct {
    int id;
    ma_sound snd;
    int active;
    int retiring;
    int loop;
    int paused;
    uint64_t retire_after_ns;
    ma_uint64 scheduled_start;
    ma_uint64 paused_at;
} muos_voice;

static struct {
    int inited;
    ma_engine engine;
    ma_resource_manager rm;
    muos_voice voices[MUOS_MAX_VOICES];
} G;

static ma_decoding_backend_vtable *g_vorbis_vtables[] = { NULL };

static uint64_t monotonic_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

static muos_voice *find_voice(int id) {
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) {
        if (G.voices[i].active && !G.voices[i].retiring && G.voices[i].id == id)
            return &G.voices[i];
    }
    return NULL;
}

static muos_voice *alloc_voice(int id) {
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) {
        if (!G.voices[i].active) {
            G.voices[i].id = id;
            return &G.voices[i];
        }
    }
    return NULL;
}

static void destroy_voice(muos_voice *voice) {
    if (!voice->active) return;
    ma_sound_uninit(&voice->snd);
    memset(voice, 0, sizeof(*voice));
    voice->id = -1;
}

static void retire_voice(muos_voice *voice) {
    if (!voice || !voice->active || voice->retiring) return;
    ma_sound_stop(&voice->snd);
    voice->retiring = 1;
    voice->id = -1;
    voice->retire_after_ns = monotonic_ns() + MUOS_RETIRE_GRACE_NS;
}

static void reap_retired_voices(void) {
    uint64_t now = monotonic_ns();
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) {
        muos_voice *voice = &G.voices[i];
        if (voice->active && voice->retiring && now >= voice->retire_after_ns)
            destroy_voice(voice);
    }
}

static void reap_finished_voices(void) {
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) {
        muos_voice *voice = &G.voices[i];
        if (voice->active && !voice->retiring && !voice->loop && !voice->paused &&
            !ma_sound_is_playing(&voice->snd) && ma_sound_at_end(&voice->snd)) {
            retire_voice(voice);
        }
    }
}

static int voice_slots_available(void) {
    int available = 0;
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) {
        if (!G.voices[i].active) available++;
    }
    return available;
}

static int init_voice(int id, const char *path, int loop, float volume,
                      ma_uint64 start_at) {
    muos_voice *voice = find_voice(id);
    if (voice) retire_voice(voice);
    reap_retired_voices();
    voice = alloc_voice(id);
    if (!voice) {
        fprintf(stderr, "[mixer] sem slots p/ id=%d\n", id);
        return -1;
    }

    ma_uint32 flags = loop ? MA_SOUND_FLAG_STREAM : MA_SOUND_FLAG_DECODE;
    ma_result result = ma_sound_init_from_file(&G.engine, path, flags, NULL, NULL, &voice->snd);
    if (result != MA_SUCCESS) {
        voice->id = -1;
        fprintf(stderr, "[mixer] init_from_file FALHOU id=%d r=%d path=%s\n",
                id, result, path);
        return -1;
    }
    voice->active = 1;
    voice->retiring = 0;
    voice->retire_after_ns = 0;
    voice->loop = loop;
    voice->paused = 0;
    voice->scheduled_start = start_at;
    voice->paused_at = 0;
    ma_sound_set_looping(&voice->snd, loop ? MA_TRUE : MA_FALSE);
    ma_sound_set_volume(&voice->snd, volume < 0 ? 1.0f : volume);
    if (start_at) ma_sound_set_start_time_in_pcm_frames(&voice->snd, start_at);
    ma_sound_start(&voice->snd);
    return 0;
}

static int core_init(void) {
    if (G.inited) return 0;
    memset(&G, 0, sizeof(G));
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) G.voices[i].id = -1;
    g_vorbis_vtables[0] = ma_decoding_backend_libvorbis;

    ma_resource_manager_config rmc = ma_resource_manager_config_init();
    rmc.ppCustomDecodingBackendVTables = g_vorbis_vtables;
    rmc.customDecodingBackendCount = 1;
    rmc.pCustomDecodingBackendUserData = NULL;
    rmc.decodedFormat = ma_format_f32;
    rmc.decodedChannels = 2;
    rmc.decodedSampleRate = 44100;
    if (ma_resource_manager_init(&rmc, &G.rm) != MA_SUCCESS) {
        fprintf(stderr, "[mixer] resource_manager_init FALHOU\n");
        return -1;
    }

    ma_engine_config ec = ma_engine_config_init();
    ec.pResourceManager = &G.rm;
    ec.channels = 2;
    ec.sampleRate = 44100;
    if (ma_engine_init(&ec, &G.engine) != MA_SUCCESS) {
        fprintf(stderr, "[mixer] engine_init FALHOU\n");
        ma_resource_manager_uninit(&G.rm);
        return -1;
    }
    G.inited = 1;
    fprintf(stderr, "[mixer] init OK on audio-owner thread\n");
    return 0;
}

static int core_play(int id, const char *path, int loop, float volume) {
    if (!G.inited || !path || !*path) return -1;
    reap_finished_voices();
    reap_retired_voices();
    return init_voice(id, path, loop, volume, 0);
}

static int core_play_pair(int intro_id, int loop_id, const char *intro_path,
                          const char *loop_path, unsigned int intro_ms, float volume) {
    if (!G.inited || !intro_path || !*intro_path || !loop_path || !*loop_path || !intro_ms)
        return -1;
    if (intro_id == loop_id) return -1;
    reap_finished_voices();
    muos_voice *old_intro = find_voice(intro_id);
    muos_voice *old_loop = find_voice(loop_id);
    if (old_intro) retire_voice(old_intro);
    if (old_loop) retire_voice(old_loop);
    reap_retired_voices();
    if (voice_slots_available() < 2) {
        fprintf(stderr, "[mixer] PLAYPAIR sem dois slots intro=%d loop=%d\n",
                intro_id, loop_id);
        return -2;
    }
    ma_uint64 now = ma_engine_get_time_in_pcm_frames(&G.engine);
    ma_uint64 at = now + ((ma_uint64)ma_engine_get_sample_rate(&G.engine) * intro_ms) / 1000;
    int intro_result = init_voice(intro_id, intro_path, 0, volume, 0);
    if (intro_result != 0) return -3;
    int loop_result = init_voice(loop_id, loop_path, 1, volume, at);
    if (loop_result != 0) {
        muos_voice *intro = find_voice(intro_id);
        if (intro) retire_voice(intro);
    }
    fprintf(stderr, "[mixer] PLAYPAIR intro=%d loop=%d ms=%u at=%llu ri=%d rl=%d\n",
            intro_id, loop_id, intro_ms, (unsigned long long)at,
            intro_result, loop_result);
    return (intro_result == 0 && loop_result == 0) ? 0 : -1;
}

static void core_stop(int id) {
    if (!G.inited) return;
    muos_voice *voice = find_voice(id);
    if (voice) retire_voice(voice);
}

static void core_volume(int id, float volume) {
    muos_voice *voice = G.inited ? find_voice(id) : NULL;
    if (voice && voice->active) ma_sound_set_volume(&voice->snd, volume);
}

static void core_pause(int id, int paused) {
    muos_voice *voice = G.inited ? find_voice(id) : NULL;
    if (!voice || !voice->active) return;
    ma_uint64 now = ma_engine_get_time_in_pcm_frames(&G.engine);
    if (paused && !voice->paused) {
        voice->paused_at = now;
        voice->paused = 1;
        ma_sound_stop(&voice->snd);
    } else if (!paused && voice->paused) {
        if (voice->scheduled_start > voice->paused_at) {
            voice->scheduled_start += now - voice->paused_at;
            ma_sound_set_start_time_in_pcm_frames(&voice->snd, voice->scheduled_start);
        }
        voice->paused = 0;
        voice->paused_at = 0;
        ma_sound_start(&voice->snd);
    }
}

static void core_stop_all(void) {
    if (!G.inited) return;
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) retire_voice(&G.voices[i]);
}

static void core_shutdown(void) {
    if (!G.inited) return;
    for (int i = 0; i < MUOS_MAX_VOICES; ++i) {
        if (G.voices[i].active) {
            ma_sound_stop(&G.voices[i].snd);
            destroy_voice(&G.voices[i]);
        }
    }
    ma_engine_uninit(&G.engine);
    ma_resource_manager_uninit(&G.rm);
    G.inited = 0;
}

static int backend_init(void *context) {
    (void)context;
    return core_init();
}

static void backend_execute(void *context, const muos_audio_command *command) {
    (void)context;
    switch (command->type) {
    case MUOS_AUDIO_PLAY:
        (void)core_play(command->id, command->path, command->loop, command->volume);
        break;
    case MUOS_AUDIO_PLAY_PAIR:
        (void)core_play_pair(command->id, command->id2, command->path, command->path2,
                             command->intro_ms, command->volume);
        break;
    case MUOS_AUDIO_STOP:
        core_stop(command->id);
        break;
    case MUOS_AUDIO_VOLUME:
        core_volume(command->id, command->volume);
        break;
    case MUOS_AUDIO_PAUSE:
        core_pause(command->id, command->paused);
        break;
    case MUOS_AUDIO_STOP_ALL:
        core_stop_all();
        break;
    case MUOS_AUDIO_SHUTDOWN:
        break;
    }
}

static void backend_reap(void *context) {
    (void)context;
    if (G.inited) {
        reap_finished_voices();
        reap_retired_voices();
    }
}

static void backend_shutdown(void *context) {
    (void)context;
    core_shutdown();
}

void muos_miniaudio_backend_get_ops(muos_audio_backend_ops *ops, void **context) {
    if (!ops) return;
    ops->init = backend_init;
    ops->execute = backend_execute;
    ops->reap = backend_reap;
    ops->shutdown = backend_shutdown;
    if (context) *context = &G;
}
