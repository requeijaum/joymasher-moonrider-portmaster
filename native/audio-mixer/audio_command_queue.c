#include "audio_command_queue.h"

#include <string.h>

static void remove_at(muos_audio_queue *queue, size_t index) {
    if (index + 1 < queue->size) {
        memmove(&queue->items[index], &queue->items[index + 1],
                (queue->size - index - 1) * sizeof(queue->items[0]));
    }
    queue->size--;
}

static int affects_id(const muos_audio_command *command, int id) {
    if (command->type == MUOS_AUDIO_STOP_ALL || command->type == MUOS_AUDIO_SHUTDOWN)
        return 0;
    if (command->id == id) return 1;
    return command->type == MUOS_AUDIO_PLAY_PAIR && command->id2 == id;
}

static size_t segment_start(const muos_audio_queue *queue) {
    for (size_t i = queue->size; i > 0; --i) {
        muos_audio_command_type type = queue->items[i - 1].type;
        if (type == MUOS_AUDIO_STOP_ALL || type == MUOS_AUDIO_SHUTDOWN) return i;
    }
    return 0;
}

static size_t remove_id_commands(muos_audio_queue *queue, size_t start,
                                 int id, int second_id, int has_second_id) {
    size_t removed = 0;
    for (size_t i = start; i < queue->size;) {
        if (affects_id(&queue->items[i], id) ||
            (has_second_id && affects_id(&queue->items[i], second_id))) {
            remove_at(queue, i);
            removed++;
        } else {
            i++;
        }
    }
    return removed;
}

static int replace_latest_scalar(muos_audio_queue *queue,
                                 const muos_audio_command *command,
                                 size_t start) {
    for (size_t i = queue->size; i > start; --i) {
        muos_audio_command *old = &queue->items[i - 1];
        if (!affects_id(old, command->id)) continue;
        if (old->type != command->type || old->id != command->id) return 0;
        muos_audio_command replacement = *command;
        replacement.sequence = ++queue->next_sequence;
        *old = replacement;
        queue->stats.coalesced++;
        return 1;
    }
    return 0;
}

static int make_room(muos_audio_queue *queue, muos_audio_command_type incoming) {
    if (queue->size < MUOS_AUDIO_QUEUE_CAPACITY) return 1;

    for (size_t i = 0; i < queue->size; ++i) {
        muos_audio_command_type type = queue->items[i].type;
        if (type == MUOS_AUDIO_VOLUME || type == MUOS_AUDIO_PAUSE) {
            remove_at(queue, i);
            queue->stats.dropped++;
            return 1;
        }
    }

    (void)incoming;
    queue->stats.dropped++;
    return 0;
}

void muos_audio_queue_init(muos_audio_queue *queue) {
    if (!queue) return;
    memset(queue, 0, sizeof(*queue));
}

int muos_audio_queue_push(muos_audio_queue *queue,
                          const muos_audio_command *command) {
    if (!queue || !command) return MUOS_AUDIO_QUEUE_DROPPED;

    if (command->type == MUOS_AUDIO_SHUTDOWN) {
        int compacted = queue->size != 0;
        queue->size = 0;
        muos_audio_command copy = *command;
        copy.sequence = ++queue->next_sequence;
        queue->items[queue->size++] = copy;
        queue->stats.pushed++;
        if (compacted) queue->stats.coalesced++;
        if (queue->stats.high_watermark < queue->size)
            queue->stats.high_watermark = queue->size;
        return compacted ? MUOS_AUDIO_QUEUE_COALESCED : MUOS_AUDIO_QUEUE_OK;
    }

    if (command->type == MUOS_AUDIO_STOP_ALL) {
        int compacted = queue->size != 0;
        queue->size = 0;
        muos_audio_command copy = *command;
        copy.sequence = ++queue->next_sequence;
        queue->items[queue->size++] = copy;
        queue->stats.pushed++;
        if (compacted) queue->stats.coalesced++;
        if (queue->stats.high_watermark < queue->size)
            queue->stats.high_watermark = queue->size;
        return compacted ? MUOS_AUDIO_QUEUE_COALESCED : MUOS_AUDIO_QUEUE_OK;
    }

    size_t start = segment_start(queue);
    if ((command->type == MUOS_AUDIO_VOLUME || command->type == MUOS_AUDIO_PAUSE) &&
        replace_latest_scalar(queue, command, start)) {
        return MUOS_AUDIO_QUEUE_COALESCED;
    }

    size_t removed = 0;
    if (command->type == MUOS_AUDIO_PLAY || command->type == MUOS_AUDIO_STOP) {
        removed = remove_id_commands(queue, start, command->id, 0, 0);
    } else if (command->type == MUOS_AUDIO_PLAY_PAIR) {
        removed = remove_id_commands(queue, start, command->id, command->id2, 1);
    }

    if (!make_room(queue, command->type)) return MUOS_AUDIO_QUEUE_DROPPED;

    muos_audio_command copy = *command;
    copy.sequence = ++queue->next_sequence;
    queue->items[queue->size++] = copy;
    queue->stats.pushed++;
    if (removed) queue->stats.coalesced++;
    if (queue->stats.high_watermark < queue->size)
        queue->stats.high_watermark = queue->size;
    return removed ? MUOS_AUDIO_QUEUE_COALESCED : MUOS_AUDIO_QUEUE_OK;
}

int muos_audio_queue_pop(muos_audio_queue *queue, muos_audio_command *out) {
    if (!queue || !out || queue->size == 0) return 0;
    *out = queue->items[0];
    remove_at(queue, 0);
    queue->stats.popped++;
    return 1;
}

size_t muos_audio_queue_size(const muos_audio_queue *queue) {
    return queue ? queue->size : 0;
}
