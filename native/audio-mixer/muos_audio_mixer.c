/* WebKit-facing audio service: bounded enqueue only, never calls miniaudio. */
#include "muos_audio_mixer.h"

#include "audio_worker.h"
#include "miniaudio_backend.h"

#include <stdio.h>
#include <string.h>

#define MUOS_AUDIO_SHUTDOWN_TIMEOUT_MS 250U

static muos_audio_worker g_worker;
static int g_service_initialized;

static int enqueue_command(const muos_audio_command *command) {
    if (!g_service_initialized || !command) return -1;
    int result = muos_audio_worker_enqueue(&g_worker, command);
    return result == MUOS_AUDIO_QUEUE_DROPPED ? -1 : 0;
}

static int copy_path(char destination[MUOS_AUDIO_PATH_CAPACITY], const char *source) {
    if (!source || !*source) return -1;
    size_t length = strlen(source);
    if (length >= MUOS_AUDIO_PATH_CAPACITY) return -1;
    memcpy(destination, source, length + 1);
    return 0;
}

int muos_mixer_init(void) {
    if (g_service_initialized) return 0;
    muos_audio_backend_ops ops;
    void *context = NULL;
    memset(&ops, 0, sizeof(ops));
    muos_miniaudio_backend_get_ops(&ops, &context);
    if (muos_audio_worker_init(&g_worker, &ops, context) != MUOS_AUDIO_WORKER_OK)
        return -1;
    if (muos_audio_worker_start(&g_worker) != MUOS_AUDIO_WORKER_OK) {
        (void)muos_audio_worker_destroy(&g_worker);
        return -1;
    }
    g_service_initialized = 1;
    fprintf(stderr, "[audio-service] worker started; GLib path is enqueue-only\n");
    return 0;
}

int muos_mixer_play(int id, const char *path, int loop, float volume) {
    muos_audio_command command = {0};
    command.type = MUOS_AUDIO_PLAY;
    command.id = id;
    command.loop = loop != 0;
    command.volume = volume;
    if (copy_path(command.path, path) != 0) return -1;
    return enqueue_command(&command);
}

int muos_mixer_play_pair(int intro_id, int loop_id, const char *intro_path,
                         const char *loop_path, unsigned int intro_ms, float volume) {
    muos_audio_command command = {0};
    command.type = MUOS_AUDIO_PLAY_PAIR;
    command.id = intro_id;
    command.id2 = loop_id;
    command.intro_ms = intro_ms;
    command.volume = volume;
    if (!intro_ms || copy_path(command.path, intro_path) != 0 ||
        copy_path(command.path2, loop_path) != 0) return -1;
    return enqueue_command(&command);
}

int muos_mixer_stop(int id) {
    muos_audio_command command = {0};
    command.type = MUOS_AUDIO_STOP;
    command.id = id;
    return enqueue_command(&command);
}

int muos_mixer_volume(int id, float volume) {
    muos_audio_command command = {0};
    command.type = MUOS_AUDIO_VOLUME;
    command.id = id;
    command.volume = volume;
    return enqueue_command(&command);
}

int muos_mixer_pause(int id, int paused) {
    muos_audio_command command = {0};
    command.type = MUOS_AUDIO_PAUSE;
    command.id = id;
    command.paused = paused != 0;
    return enqueue_command(&command);
}

void muos_mixer_stop_all(void) {
    muos_audio_command command = {0};
    command.type = MUOS_AUDIO_STOP_ALL;
    (void)muos_audio_worker_enqueue(&g_worker, &command);
}

void muos_mixer_reap(void) {
    /* The audio-owner thread performs periodic reap independently of GLib. */
}

void muos_mixer_get_stats(muos_audio_worker_stats *stats) {
    if (!stats) return;
    if (!g_service_initialized) {
        memset(stats, 0, sizeof(*stats));
        stats->state = MUOS_AUDIO_WORKER_NEW;
        return;
    }
    muos_audio_worker_get_stats(&g_worker, stats);
}

void muos_mixer_shutdown(void) {
    if (!g_service_initialized) return;
    int result = muos_audio_worker_stop(&g_worker, MUOS_AUDIO_SHUTDOWN_TIMEOUT_MS);
    if (result == MUOS_AUDIO_WORKER_TIMEOUT) {
        fprintf(stderr, "[audio-service] worker shutdown timed out; process exit remains unblocked\n");
        return;
    }
    if (result != MUOS_AUDIO_WORKER_TIMEOUT) {
        (void)muos_audio_worker_destroy(&g_worker);
    }
    if (result != MUOS_AUDIO_WORKER_OK) {
        fprintf(stderr, "[audio-service] worker shutdown failed=%d\n", result);
    }
    g_service_initialized = 0;
}
