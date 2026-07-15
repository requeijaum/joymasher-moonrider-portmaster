#include "input_watch.h"

void muos_input_watch_init(muos_input_watch *watch, int64_t now_us) {
    atomic_init(&watch->last_pulse_us, now_us);
    atomic_init(&watch->stalled, 0);
}

muos_input_watch_event muos_input_watch_check(
    muos_input_watch *watch, int64_t now_us, int64_t threshold_us) {
    int64_t last = atomic_load_explicit(&watch->last_pulse_us, memory_order_acquire);
    int expected = 0;
    if (now_us - last < threshold_us) return MUOS_INPUT_WATCH_NONE;
    if (atomic_compare_exchange_strong_explicit(
            &watch->stalled, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        return MUOS_INPUT_WATCH_STALL;
    }
    return MUOS_INPUT_WATCH_NONE;
}

muos_input_watch_event muos_input_watch_note_pulse(
    muos_input_watch *watch, int64_t now_us) {
    atomic_store_explicit(&watch->last_pulse_us, now_us, memory_order_release);
    if (atomic_exchange_explicit(&watch->stalled, 0, memory_order_acq_rel)) {
        return MUOS_INPUT_WATCH_RECOVER;
    }
    return MUOS_INPUT_WATCH_NONE;
}
