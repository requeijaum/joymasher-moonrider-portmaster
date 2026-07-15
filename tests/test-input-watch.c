#include <assert.h>
#include <stdint.h>

#include "../native/backend/input_watch.h"

int main(void) {
    muos_input_watch watch;
    muos_input_watch_init(&watch, 1000000);

    assert(muos_input_watch_check(&watch, 1099999, 100000) == MUOS_INPUT_WATCH_NONE);
    assert(muos_input_watch_check(&watch, 1100000, 100000) == MUOS_INPUT_WATCH_STALL);
    assert(muos_input_watch_check(&watch, 1500000, 100000) == MUOS_INPUT_WATCH_NONE);

    assert(muos_input_watch_note_pulse(&watch, 1500001) == MUOS_INPUT_WATCH_RECOVER);
    assert(muos_input_watch_note_pulse(&watch, 1500010) == MUOS_INPUT_WATCH_NONE);
    assert(muos_input_watch_check(&watch, 1600010, 100000) == MUOS_INPUT_WATCH_STALL);
    return 0;
}
