#define _POSIX_C_SOURCE 200809L
#include "audio_worker.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#ifndef ETIMEDOUT
#include <errno.h>
#endif

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int initialized;
    int entered;
    int release;
    int shutdowns;
    int executes;
    int reaps;
    int block_reap;
    int reap_entered;
    pthread_t owner;
} fake_backend;

static int fake_init(void *ctx) {
    fake_backend *fake = ctx;
    pthread_mutex_lock(&fake->mutex);
    fake->initialized = 1;
    fake->owner = pthread_self();
    pthread_cond_broadcast(&fake->cond);
    pthread_mutex_unlock(&fake->mutex);
    return 0;
}

static void fake_execute(void *ctx, const muos_audio_command *command) {
    fake_backend *fake = ctx;
    assert(pthread_equal(fake->owner, pthread_self()));
    pthread_mutex_lock(&fake->mutex);
    fake->executes++;
    if (command->type == MUOS_AUDIO_PLAY) {
        fake->entered = 1;
        pthread_cond_broadcast(&fake->cond);
        while (!fake->release) pthread_cond_wait(&fake->cond, &fake->mutex);
    }
    pthread_mutex_unlock(&fake->mutex);
}

static void fake_reap(void *ctx) {
    fake_backend *fake = ctx;
    assert(pthread_equal(fake->owner, pthread_self()));
    pthread_mutex_lock(&fake->mutex);
    fake->reaps++;
    if (fake->block_reap) {
        fake->reap_entered = 1;
        pthread_cond_broadcast(&fake->cond);
        while (!fake->release) pthread_cond_wait(&fake->cond, &fake->mutex);
    }
    pthread_mutex_unlock(&fake->mutex);
}

static void fake_shutdown(void *ctx) {
    fake_backend *fake = ctx;
    assert(pthread_equal(fake->owner, pthread_self()));
    pthread_mutex_lock(&fake->mutex);
    fake->shutdowns++;
    pthread_mutex_unlock(&fake->mutex);
}

static void wait_for_flag(fake_backend *fake, int *flag) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += 2;
    pthread_mutex_lock(&fake->mutex);
    while (!*flag) {
        int rc = pthread_cond_timedwait(&fake->cond, &fake->mutex, &deadline);
        assert(rc != ETIMEDOUT);
    }
    pthread_mutex_unlock(&fake->mutex);
}

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1000.0 +
           (double)(b.tv_nsec - a.tv_nsec) / 1000000.0;
}

int main(void) {
    fake_backend fake;
    memset(&fake, 0, sizeof(fake));
    assert(pthread_mutex_init(&fake.mutex, NULL) == 0);
    assert(pthread_cond_init(&fake.cond, NULL) == 0);

    muos_audio_backend_ops ops = {
        .init = fake_init,
        .execute = fake_execute,
        .reap = fake_reap,
        .shutdown = fake_shutdown,
    };
    muos_audio_worker worker;
    assert(muos_audio_worker_init(&worker, &ops, &fake) == 0);
    assert(muos_audio_worker_start(&worker) == 0);
    wait_for_flag(&fake, &fake.initialized);
    assert(!pthread_equal(fake.owner, pthread_self()));

    muos_audio_command play = {0};
    play.type = MUOS_AUDIO_PLAY;
    play.id = 1;
    strcpy(play.path, "/tmp/block.ogg");
    assert(muos_audio_worker_enqueue(&worker, &play) >= 0);
    wait_for_flag(&fake, &fake.entered);

    struct timespec begin, end;
    clock_gettime(CLOCK_MONOTONIC, &begin);
    for (int i = 0; i < 50000; ++i) {
        muos_audio_command volume = {0};
        volume.type = MUOS_AUDIO_VOLUME;
        volume.id = i % 32;
        volume.volume = (float)(i % 100) / 100.0f;
        int rc = muos_audio_worker_enqueue(&worker, &volume);
        assert(rc >= MUOS_AUDIO_QUEUE_DROPPED);
    }
    clock_gettime(CLOCK_MONOTONIC, &end);
    assert(elapsed_ms(begin, end) < 500.0);

    muos_audio_worker_stats stats;
    muos_audio_worker_get_stats(&worker, &stats);
    assert(stats.queue_depth <= MUOS_AUDIO_QUEUE_CAPACITY);
    assert(stats.coalesced > 49000);
    assert(stats.current_operation == MUOS_AUDIO_PLAY);
    assert(stats.state == MUOS_AUDIO_WORKER_RUNNING);

    muos_audio_worker_set_stall_timeout(&worker, 10);
    struct timespec breaker_wait = { .tv_sec = 0, .tv_nsec = 20000000L };
    nanosleep(&breaker_wait, NULL);
    muos_audio_command rejected = {0};
    rejected.type = MUOS_AUDIO_VOLUME;
    rejected.id = 99;
    assert(muos_audio_worker_enqueue(&worker, &rejected) == MUOS_AUDIO_QUEUE_DROPPED);
    muos_audio_worker_get_stats(&worker, &stats);
    assert(stats.breaker_open == 1);
    assert(stats.stall_events == 1);
    assert(stats.queue_depth == 0);

    assert(muos_audio_worker_stop(&worker, 20) == MUOS_AUDIO_WORKER_TIMEOUT);

    pthread_mutex_lock(&fake.mutex);
    fake.release = 1;
    pthread_cond_broadcast(&fake.cond);
    pthread_mutex_unlock(&fake.mutex);

    assert(muos_audio_worker_stop(&worker, 2000) == MUOS_AUDIO_WORKER_OK);
    muos_audio_worker_get_stats(&worker, &stats);
    assert(stats.state == MUOS_AUDIO_WORKER_STOPPED);
    assert(stats.processed >= 1);
    assert(stats.current_operation == 0);
    assert(fake.shutdowns == 1);
    assert(muos_audio_worker_destroy(&worker) == 0);

    pthread_cond_destroy(&fake.cond);
    pthread_mutex_destroy(&fake.mutex);

    fake_backend reap_fake;
    memset(&reap_fake, 0, sizeof(reap_fake));
    reap_fake.block_reap = 1;
    assert(pthread_mutex_init(&reap_fake.mutex, NULL) == 0);
    assert(pthread_cond_init(&reap_fake.cond, NULL) == 0);
    muos_audio_worker reap_worker;
    assert(muos_audio_worker_init(&reap_worker, &ops, &reap_fake) == 0);
    assert(muos_audio_worker_start(&reap_worker) == 0);
    wait_for_flag(&reap_fake, &reap_fake.initialized);
    wait_for_flag(&reap_fake, &reap_fake.reap_entered);
    muos_audio_worker_set_stall_timeout(&reap_worker, 10);
    nanosleep(&breaker_wait, NULL);
    assert(muos_audio_worker_enqueue(&reap_worker, &rejected) == MUOS_AUDIO_QUEUE_DROPPED);
    muos_audio_worker_get_stats(&reap_worker, &stats);
    assert(stats.breaker_open == 1);
    assert(stats.current_operation == MUOS_AUDIO_OPERATION_REAP);
    assert(muos_audio_worker_stop(&reap_worker, 20) == MUOS_AUDIO_WORKER_TIMEOUT);
    pthread_mutex_lock(&reap_fake.mutex);
    reap_fake.release = 1;
    pthread_cond_broadcast(&reap_fake.cond);
    pthread_mutex_unlock(&reap_fake.mutex);
    assert(muos_audio_worker_stop(&reap_worker, 2000) == MUOS_AUDIO_WORKER_OK);
    assert(muos_audio_worker_destroy(&reap_worker) == 0);
    pthread_cond_destroy(&reap_fake.cond);
    pthread_mutex_destroy(&reap_fake.mutex);

    puts("test-audio-worker: OK");
    return 0;
}
