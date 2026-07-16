#ifndef MUOS_AUDIO_COMMAND_QUEUE_H
#define MUOS_AUDIO_COMMAND_QUEUE_H

#include <stddef.h>
#include <stdint.h>

#define MUOS_AUDIO_QUEUE_CAPACITY 128
#define MUOS_AUDIO_PATH_CAPACITY 512

typedef enum {
    MUOS_AUDIO_PLAY = 1,
    MUOS_AUDIO_PLAY_PAIR,
    MUOS_AUDIO_STOP,
    MUOS_AUDIO_VOLUME,
    MUOS_AUDIO_PAUSE,
    MUOS_AUDIO_STOP_ALL,
    MUOS_AUDIO_SHUTDOWN
} muos_audio_command_type;

typedef struct {
    muos_audio_command_type type;
    int id;
    int id2;
    int loop;
    int paused;
    float volume;
    unsigned int intro_ms;
    uint64_t sequence;
    char path[MUOS_AUDIO_PATH_CAPACITY];
    char path2[MUOS_AUDIO_PATH_CAPACITY];
} muos_audio_command;

typedef struct {
    uint64_t pushed;
    uint64_t popped;
    uint64_t coalesced;
    uint64_t dropped;
    size_t high_watermark;
} muos_audio_queue_stats;

typedef struct {
    muos_audio_command items[MUOS_AUDIO_QUEUE_CAPACITY];
    size_t size;
    uint64_t next_sequence;
    muos_audio_queue_stats stats;
} muos_audio_queue;

enum {
    MUOS_AUDIO_QUEUE_DROPPED = -1,
    MUOS_AUDIO_QUEUE_OK = 0,
    MUOS_AUDIO_QUEUE_COALESCED = 1
};

void muos_audio_queue_init(muos_audio_queue *queue);
int muos_audio_queue_push(muos_audio_queue *queue, const muos_audio_command *command);
int muos_audio_queue_pop(muos_audio_queue *queue, muos_audio_command *out);
size_t muos_audio_queue_size(const muos_audio_queue *queue);

#endif
