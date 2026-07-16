#ifndef MUOS_AUDIO_WORKER_H
#define MUOS_AUDIO_WORKER_H

#include "audio_command_queue.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>

typedef struct muos_audio_backend_ops muos_audio_backend_ops;

struct muos_audio_backend_ops {
    int (*init)(void *context);
    void (*execute)(void *context, const muos_audio_command *command);
    void (*reap)(void *context);
    void (*shutdown)(void *context);
};

typedef enum {
    MUOS_AUDIO_WORKER_NEW = 0,
    MUOS_AUDIO_WORKER_STARTING,
    MUOS_AUDIO_WORKER_RUNNING,
    MUOS_AUDIO_WORKER_FAILED,
    MUOS_AUDIO_WORKER_STOPPED
} muos_audio_worker_state;

typedef struct {
    size_t queue_depth;
    size_t queue_high_watermark;
    uint64_t enqueued;
    uint64_t processed;
    uint64_t coalesced;
    uint64_t dropped;
    uint64_t heartbeat_ns;
    int current_operation;
    int breaker_open;
    uint64_t stall_events;
    muos_audio_worker_state state;
} muos_audio_worker_stats;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t wake;
    pthread_cond_t state_changed;
    pthread_t thread;
    int thread_created;
    int thread_joined;
    muos_audio_queue queue;
    muos_audio_backend_ops ops;
    void *context;
    atomic_uint_fast64_t processed;
    atomic_uint_fast64_t heartbeat_ns;
    atomic_uint_fast64_t stall_events;
    atomic_uint_fast64_t stall_timeout_ns;
    atomic_int current_operation;
    atomic_int breaker_open;
    atomic_int state;
} muos_audio_worker;

enum {
    MUOS_AUDIO_WORKER_TIMEOUT = -2,
    MUOS_AUDIO_WORKER_ERROR = -1,
    MUOS_AUDIO_WORKER_OK = 0
};

enum {
    MUOS_AUDIO_OPERATION_INIT = 1001,
    MUOS_AUDIO_OPERATION_REAP = 1002,
    MUOS_AUDIO_OPERATION_SHUTDOWN = 1003
};

int muos_audio_worker_init(muos_audio_worker *worker,
                           const muos_audio_backend_ops *ops,
                           void *context);
int muos_audio_worker_start(muos_audio_worker *worker);
int muos_audio_worker_enqueue(muos_audio_worker *worker,
                              const muos_audio_command *command);
void muos_audio_worker_set_stall_timeout(muos_audio_worker *worker,
                                         unsigned int timeout_ms);
int muos_audio_worker_stop(muos_audio_worker *worker, unsigned int timeout_ms);
void muos_audio_worker_get_stats(muos_audio_worker *worker,
                                 muos_audio_worker_stats *out);
int muos_audio_worker_destroy(muos_audio_worker *worker);

#endif
