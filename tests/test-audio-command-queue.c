#include "audio_command_queue.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static muos_audio_command play_cmd(int id, const char *path) {
    muos_audio_command c = {0};
    c.type = MUOS_AUDIO_PLAY;
    c.id = id;
    c.loop = 0;
    c.volume = 0.75f;
    snprintf(c.path, sizeof(c.path), "%s", path);
    return c;
}

static muos_audio_command simple_cmd(muos_audio_command_type type, int id) {
    muos_audio_command c = {0};
    c.type = type;
    c.id = id;
    return c;
}

static void test_fifo_and_owned_paths(void) {
    muos_audio_queue q;
    muos_audio_queue_init(&q);
    char path[64] = "/tmp/first.ogg";
    muos_audio_command a = play_cmd(1, path);
    muos_audio_command b = play_cmd(2, "/tmp/second.ogg");
    assert(muos_audio_queue_push(&q, &a) == MUOS_AUDIO_QUEUE_OK);
    assert(muos_audio_queue_push(&q, &b) == MUOS_AUDIO_QUEUE_OK);
    strcpy(path, "/tmp/mutated.ogg");

    muos_audio_command out = {0};
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.id == 1);
    assert(strcmp(out.path, "/tmp/first.ogg") == 0);
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.id == 2);
    assert(!muos_audio_queue_pop(&q, &out));
}

static void test_latest_volume_and_pause_coalesce(void) {
    muos_audio_queue q;
    muos_audio_queue_init(&q);
    muos_audio_command c = simple_cmd(MUOS_AUDIO_VOLUME, 7);
    c.volume = 0.2f;
    assert(muos_audio_queue_push(&q, &c) == MUOS_AUDIO_QUEUE_OK);
    c.volume = 0.8f;
    assert(muos_audio_queue_push(&q, &c) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_size(&q) == 1);

    muos_audio_command out = {0};
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.type == MUOS_AUDIO_VOLUME);
    assert(fabsf(out.volume - 0.8f) < 0.0001f);
    assert(q.stats.coalesced == 1);

    c = simple_cmd(MUOS_AUDIO_PAUSE, 9);
    c.paused = 1;
    assert(muos_audio_queue_push(&q, &c) == MUOS_AUDIO_QUEUE_OK);
    c.paused = 0;
    assert(muos_audio_queue_push(&q, &c) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.paused == 0);
}

static void test_final_state_compaction(void) {
    muos_audio_queue q;
    muos_audio_queue_init(&q);
    muos_audio_command p = play_cmd(11, "/tmp/a.ogg");
    muos_audio_command v = simple_cmd(MUOS_AUDIO_VOLUME, 11);
    v.volume = 0.3f;
    muos_audio_command s = simple_cmd(MUOS_AUDIO_STOP, 11);
    assert(muos_audio_queue_push(&q, &p) == MUOS_AUDIO_QUEUE_OK);
    assert(muos_audio_queue_push(&q, &v) == MUOS_AUDIO_QUEUE_OK);
    assert(muos_audio_queue_push(&q, &s) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_size(&q) == 1);
    assert(muos_audio_queue_push(&q, &s) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_size(&q) == 1);

    p = play_cmd(11, "/tmp/b.ogg");
    assert(muos_audio_queue_push(&q, &p) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_size(&q) == 1);
    muos_audio_command out = {0};
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.type == MUOS_AUDIO_PLAY);
    assert(strcmp(out.path, "/tmp/b.ogg") == 0);
}

static void test_playpair_is_atomic_and_stopall_supersedes(void) {
    muos_audio_queue q;
    muos_audio_queue_init(&q);
    muos_audio_command v1 = simple_cmd(MUOS_AUDIO_VOLUME, 20);
    muos_audio_command v2 = simple_cmd(MUOS_AUDIO_VOLUME, 21);
    assert(muos_audio_queue_push(&q, &v1) == MUOS_AUDIO_QUEUE_OK);
    assert(muos_audio_queue_push(&q, &v2) == MUOS_AUDIO_QUEUE_OK);

    muos_audio_command pair = {0};
    pair.type = MUOS_AUDIO_PLAY_PAIR;
    pair.id = 20;
    pair.id2 = 21;
    pair.volume = 0.9f;
    pair.intro_ms = 1234;
    strcpy(pair.path, "/tmp/intro.ogg");
    strcpy(pair.path2, "/tmp/loop.ogg");
    assert(muos_audio_queue_push(&q, &pair) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_size(&q) == 1);

    muos_audio_command out = {0};
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.type == MUOS_AUDIO_PLAY_PAIR);
    assert(out.id == 20 && out.id2 == 21);
    assert(strcmp(out.path2, "/tmp/loop.ogg") == 0);

    muos_audio_command one = play_cmd(1, "/tmp/one.ogg");
    muos_audio_command two = play_cmd(2, "/tmp/two.ogg");
    assert(muos_audio_queue_push(&q, &one) == MUOS_AUDIO_QUEUE_OK);
    assert(muos_audio_queue_push(&q, &two) == MUOS_AUDIO_QUEUE_OK);
    muos_audio_command all = simple_cmd(MUOS_AUDIO_STOP_ALL, 0);
    assert(muos_audio_queue_push(&q, &all) == MUOS_AUDIO_QUEUE_COALESCED);
    assert(muos_audio_queue_size(&q) == 1);
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.type == MUOS_AUDIO_STOP_ALL);
}

static void test_storm_is_bounded_and_shutdown_is_never_lost(void) {
    muos_audio_queue q;
    muos_audio_queue_init(&q);
    for (int i = 0; i < 50000; ++i) {
        muos_audio_command v = simple_cmd(MUOS_AUDIO_VOLUME, i % 32);
        v.volume = (float)(i % 100) / 100.0f;
        int rc = muos_audio_queue_push(&q, &v);
        assert(rc == MUOS_AUDIO_QUEUE_OK || rc == MUOS_AUDIO_QUEUE_COALESCED || rc == MUOS_AUDIO_QUEUE_DROPPED);
        assert(muos_audio_queue_size(&q) <= MUOS_AUDIO_QUEUE_CAPACITY);
    }
    assert(q.stats.coalesced > 49000);

    muos_audio_command shutdown = simple_cmd(MUOS_AUDIO_SHUTDOWN, 0);
    assert(muos_audio_queue_push(&q, &shutdown) != MUOS_AUDIO_QUEUE_DROPPED);
    assert(muos_audio_queue_size(&q) == 1);
    muos_audio_command out = {0};
    assert(muos_audio_queue_pop(&q, &out));
    assert(out.type == MUOS_AUDIO_SHUTDOWN);
}

int main(void) {
    test_fifo_and_owned_paths();
    test_latest_volume_and_pause_coalesce();
    test_final_state_compaction();
    test_playpair_is_atomic_and_stopall_supersedes();
    test_storm_is_bounded_and_shutdown_is_never_lost();
    puts("test-audio-command-queue: OK");
    return 0;
}
