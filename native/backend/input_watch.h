#ifndef MUOS_INPUT_WATCH_H
#define MUOS_INPUT_WATCH_H

#include <stdatomic.h>
#include <stdint.h>

typedef enum {
    MUOS_INPUT_WATCH_NONE = 0,
    MUOS_INPUT_WATCH_STALL = 1,
    MUOS_INPUT_WATCH_RECOVER = 2
} muos_input_watch_event;

typedef struct {
    atomic_llong last_pulse_us;
    atomic_int stalled;
} muos_input_watch;

void muos_input_watch_init(muos_input_watch *watch, int64_t now_us);
muos_input_watch_event muos_input_watch_check(
    muos_input_watch *watch, int64_t now_us, int64_t threshold_us);
muos_input_watch_event muos_input_watch_note_pulse(
    muos_input_watch *watch, int64_t now_us);

#endif
