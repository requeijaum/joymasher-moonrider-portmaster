#define _POSIX_C_SOURCE 200809L
#include "audio_worker.h"

#include <errno.h>
#include <string.h>
#include <time.h>

#define MUOS_AUDIO_REAP_INTERVAL_MS 50
#define MUOS_AUDIO_DEFAULT_STALL_TIMEOUT_NS UINT64_C(2000000000)

static uint64_t monotonic_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

static struct timespec realtime_deadline(unsigned int timeout_ms) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += (time_t)(timeout_ms / 1000U);
    deadline.tv_nsec += (long)(timeout_ms % 1000U) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000L;
    }
    return deadline;
}

static void set_state(muos_audio_worker *worker, muos_audio_worker_state state) {
    atomic_store_explicit(&worker->state, state, memory_order_release);
    pthread_mutex_lock(&worker->mutex);
    pthread_cond_broadcast(&worker->state_changed);
    pthread_mutex_unlock(&worker->mutex);
}

static void *worker_main(void *opaque) {
    muos_audio_worker *worker = opaque;
    atomic_store_explicit(&worker->current_operation, MUOS_AUDIO_OPERATION_INIT,
                          memory_order_release);
    atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(), memory_order_release);
    if (worker->ops.init(worker->context) != 0) {
        atomic_store_explicit(&worker->current_operation, 0, memory_order_release);
        set_state(worker, MUOS_AUDIO_WORKER_FAILED);
        return NULL;
    }
    atomic_store_explicit(&worker->current_operation, 0, memory_order_release);
    atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(), memory_order_release);
    set_state(worker, MUOS_AUDIO_WORKER_RUNNING);

    int stopping = 0;
    while (!stopping) {
        muos_audio_command command;
        int have_command = 0;
        struct timespec deadline = realtime_deadline(MUOS_AUDIO_REAP_INTERVAL_MS);

        pthread_mutex_lock(&worker->mutex);
        while (muos_audio_queue_size(&worker->queue) == 0) {
            int rc = pthread_cond_timedwait(&worker->wake, &worker->mutex, &deadline);
            if (rc == ETIMEDOUT) break;
        }
        have_command = muos_audio_queue_pop(&worker->queue, &command);
        pthread_mutex_unlock(&worker->mutex);

        if (have_command) {
            if (command.type == MUOS_AUDIO_SHUTDOWN) {
                stopping = 1;
                continue;
            }
            atomic_store_explicit(&worker->current_operation, command.type,
                                  memory_order_release);
            atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(),
                                  memory_order_release);
            worker->ops.execute(worker->context, &command);
            atomic_fetch_add_explicit(&worker->processed, 1, memory_order_relaxed);
            atomic_store_explicit(&worker->current_operation, 0, memory_order_release);
            atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(),
                                  memory_order_release);
        } else if (worker->ops.reap) {
            atomic_store_explicit(&worker->current_operation, MUOS_AUDIO_OPERATION_REAP,
                                  memory_order_release);
            atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(),
                                  memory_order_release);
            worker->ops.reap(worker->context);
            atomic_store_explicit(&worker->current_operation, 0, memory_order_release);
            atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(),
                                  memory_order_release);
        }
    }

    atomic_store_explicit(&worker->current_operation, MUOS_AUDIO_OPERATION_SHUTDOWN,
                          memory_order_release);
    atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(), memory_order_release);
    if (worker->ops.shutdown) worker->ops.shutdown(worker->context);
    atomic_store_explicit(&worker->current_operation, 0, memory_order_release);
    atomic_store_explicit(&worker->heartbeat_ns, monotonic_ns(), memory_order_release);
    set_state(worker, MUOS_AUDIO_WORKER_STOPPED);
    return NULL;
}

int muos_audio_worker_init(muos_audio_worker *worker,
                           const muos_audio_backend_ops *ops,
                           void *context) {
    if (!worker || !ops || !ops->init || !ops->execute) return MUOS_AUDIO_WORKER_ERROR;
    memset(worker, 0, sizeof(*worker));
    if (pthread_mutex_init(&worker->mutex, NULL) != 0) return MUOS_AUDIO_WORKER_ERROR;
    if (pthread_cond_init(&worker->wake, NULL) != 0) {
        pthread_mutex_destroy(&worker->mutex);
        return MUOS_AUDIO_WORKER_ERROR;
    }
    if (pthread_cond_init(&worker->state_changed, NULL) != 0) {
        pthread_cond_destroy(&worker->wake);
        pthread_mutex_destroy(&worker->mutex);
        return MUOS_AUDIO_WORKER_ERROR;
    }
    muos_audio_queue_init(&worker->queue);
    worker->ops = *ops;
    worker->context = context;
    atomic_init(&worker->processed, 0);
    atomic_init(&worker->heartbeat_ns, 0);
    atomic_init(&worker->stall_events, 0);
    atomic_init(&worker->stall_timeout_ns, MUOS_AUDIO_DEFAULT_STALL_TIMEOUT_NS);
    atomic_init(&worker->current_operation, 0);
    atomic_init(&worker->breaker_open, 0);
    atomic_init(&worker->state, MUOS_AUDIO_WORKER_NEW);
    return MUOS_AUDIO_WORKER_OK;
}

int muos_audio_worker_start(muos_audio_worker *worker) {
    if (!worker || worker->thread_created) return MUOS_AUDIO_WORKER_ERROR;
    atomic_store_explicit(&worker->state, MUOS_AUDIO_WORKER_STARTING, memory_order_release);
    if (pthread_create(&worker->thread, NULL, worker_main, worker) != 0) {
        atomic_store_explicit(&worker->state, MUOS_AUDIO_WORKER_FAILED, memory_order_release);
        return MUOS_AUDIO_WORKER_ERROR;
    }
    worker->thread_created = 1;
    return MUOS_AUDIO_WORKER_OK;
}

int muos_audio_worker_enqueue(muos_audio_worker *worker,
                              const muos_audio_command *command) {
    if (!worker || !command || !worker->thread_created)
        return MUOS_AUDIO_QUEUE_DROPPED;
    muos_audio_worker_state state = atomic_load_explicit(&worker->state, memory_order_acquire);
    if (state == MUOS_AUDIO_WORKER_FAILED || state == MUOS_AUDIO_WORKER_STOPPED)
        return MUOS_AUDIO_QUEUE_DROPPED;

    pthread_mutex_lock(&worker->mutex);
    if (command->type != MUOS_AUDIO_SHUTDOWN) {
        int breaker = atomic_load_explicit(&worker->breaker_open, memory_order_acquire);
        int operation = atomic_load_explicit(&worker->current_operation, memory_order_acquire);
        uint64_t heartbeat = atomic_load_explicit(&worker->heartbeat_ns, memory_order_acquire);
        uint64_t timeout = atomic_load_explicit(&worker->stall_timeout_ns, memory_order_relaxed);
        uint64_t now = monotonic_ns();
        if (!breaker && operation != 0 && heartbeat != 0 && now > heartbeat &&
            now - heartbeat >= timeout) {
            worker->queue.stats.dropped += worker->queue.size + 1;
            worker->queue.size = 0;
            atomic_store_explicit(&worker->breaker_open, 1, memory_order_release);
            atomic_fetch_add_explicit(&worker->stall_events, 1, memory_order_relaxed);
            pthread_mutex_unlock(&worker->mutex);
            return MUOS_AUDIO_QUEUE_DROPPED;
        }
        if (breaker) {
            worker->queue.stats.dropped++;
            pthread_mutex_unlock(&worker->mutex);
            return MUOS_AUDIO_QUEUE_DROPPED;
        }
    }
    int rc = muos_audio_queue_push(&worker->queue, command);
    pthread_cond_signal(&worker->wake);
    pthread_mutex_unlock(&worker->mutex);
    return rc;
}

void muos_audio_worker_set_stall_timeout(muos_audio_worker *worker,
                                         unsigned int timeout_ms) {
    if (!worker) return;
    uint64_t timeout_ns = (uint64_t)(timeout_ms ? timeout_ms : 1U) * UINT64_C(1000000);
    atomic_store_explicit(&worker->stall_timeout_ns, timeout_ns, memory_order_release);
}

int muos_audio_worker_stop(muos_audio_worker *worker, unsigned int timeout_ms) {
    if (!worker || !worker->thread_created) return MUOS_AUDIO_WORKER_ERROR;

    muos_audio_worker_state state = atomic_load_explicit(&worker->state, memory_order_acquire);
    if (state != MUOS_AUDIO_WORKER_STOPPED && state != MUOS_AUDIO_WORKER_FAILED) {
        muos_audio_command shutdown_command;
        memset(&shutdown_command, 0, sizeof(shutdown_command));
        shutdown_command.type = MUOS_AUDIO_SHUTDOWN;
        (void)muos_audio_worker_enqueue(worker, &shutdown_command);
    }

    struct timespec deadline = realtime_deadline(timeout_ms);
    pthread_mutex_lock(&worker->mutex);
    for (;;) {
        state = atomic_load_explicit(&worker->state, memory_order_acquire);
        if (state == MUOS_AUDIO_WORKER_STOPPED || state == MUOS_AUDIO_WORKER_FAILED) break;
        int rc = pthread_cond_timedwait(&worker->state_changed, &worker->mutex, &deadline);
        if (rc == ETIMEDOUT) {
            pthread_mutex_unlock(&worker->mutex);
            return MUOS_AUDIO_WORKER_TIMEOUT;
        }
    }
    pthread_mutex_unlock(&worker->mutex);

    if (!worker->thread_joined) {
        if (pthread_join(worker->thread, NULL) != 0) return MUOS_AUDIO_WORKER_ERROR;
        worker->thread_joined = 1;
    }
    return state == MUOS_AUDIO_WORKER_STOPPED ? MUOS_AUDIO_WORKER_OK : MUOS_AUDIO_WORKER_ERROR;
}

void muos_audio_worker_get_stats(muos_audio_worker *worker,
                                 muos_audio_worker_stats *out) {
    if (!worker || !out) return;
    memset(out, 0, sizeof(*out));
    pthread_mutex_lock(&worker->mutex);
    out->queue_depth = worker->queue.size;
    out->queue_high_watermark = worker->queue.stats.high_watermark;
    out->enqueued = worker->queue.stats.pushed;
    out->coalesced = worker->queue.stats.coalesced;
    out->dropped = worker->queue.stats.dropped;
    pthread_mutex_unlock(&worker->mutex);
    out->processed = atomic_load_explicit(&worker->processed, memory_order_acquire);
    out->heartbeat_ns = atomic_load_explicit(&worker->heartbeat_ns, memory_order_acquire);
    out->current_operation = atomic_load_explicit(&worker->current_operation, memory_order_acquire);
    out->breaker_open = atomic_load_explicit(&worker->breaker_open, memory_order_acquire);
    out->stall_events = atomic_load_explicit(&worker->stall_events, memory_order_acquire);
    out->state = (muos_audio_worker_state)atomic_load_explicit(&worker->state, memory_order_acquire);
}

int muos_audio_worker_destroy(muos_audio_worker *worker) {
    if (!worker) return MUOS_AUDIO_WORKER_ERROR;
    muos_audio_worker_state state = atomic_load_explicit(&worker->state, memory_order_acquire);
    if (worker->thread_created && (!worker->thread_joined ||
        (state != MUOS_AUDIO_WORKER_STOPPED && state != MUOS_AUDIO_WORKER_FAILED))) {
        return MUOS_AUDIO_WORKER_ERROR;
    }
    pthread_cond_destroy(&worker->state_changed);
    pthread_cond_destroy(&worker->wake);
    pthread_mutex_destroy(&worker->mutex);
    return MUOS_AUDIO_WORKER_OK;
}
