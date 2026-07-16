#include <assert.h>
#include <string.h>

#include "../native/backend/input_mailbox.h"

static void clear(float *buttons, float *axes) {
    memset(buttons, 0, sizeof(float) * MUOS_INPUT_MAILBOX_BUTTONS);
    memset(axes, 0, sizeof(float) * MUOS_INPUT_MAILBOX_AXES);
}

int main(void) {
    muos_input_mailbox mailbox;
    muos_input_snapshot first, latest;
    float buttons[MUOS_INPUT_MAILBOX_BUTTONS];
    float axes[MUOS_INPUT_MAILBOX_AXES];

    muos_input_mailbox_init(&mailbox);
    clear(buttons, axes);

    /* A press starts the only allowed async delivery. */
    buttons[0] = 1.0f;
    assert(muos_input_mailbox_update(&mailbox, buttons, axes) == 1);
    assert(muos_input_mailbox_begin_send(&mailbox, &first) == 1);
    assert(first.seq == 1 && first.buttons[0] == 1.0f && first.press_edges[0]);
    assert(muos_input_mailbox_begin_send(&mailbox, &latest) == 0);

    /* While seq=1 is in flight: A releases; B completes a short tap; X is held. */
    clear(buttons, axes);
    assert(muos_input_mailbox_update(&mailbox, buttons, axes) == 2);
    buttons[1] = 1.0f;
    assert(muos_input_mailbox_update(&mailbox, buttons, axes) == 3);
    buttons[1] = 0.0f;
    buttons[2] = 1.0f;
    axes[0] = -0.75f;
    assert(muos_input_mailbox_update(&mailbox, buttons, axes) == 4);

    /* ACK seq=1: pending state is latest, but B's coalesced rising edge survives. */
    muos_input_mailbox_complete(&mailbox, &first, 1);
    assert(muos_input_mailbox_begin_send(&mailbox, &latest) == 1);
    assert(latest.seq == 4);
    assert(latest.buttons[0] == 0.0f && latest.buttons[1] == 0.0f);
    assert(latest.buttons[2] == 1.0f && latest.axes[0] == -0.75f);
    assert(!latest.press_edges[0]);
    assert(latest.press_edges[1]);
    assert(latest.press_edges[2]);

    /* A newer B edge during delivery must not be cleared by the older ACK. */
    buttons[1] = 1.0f;
    assert(muos_input_mailbox_update(&mailbox, buttons, axes) == 5);
    muos_input_mailbox_complete(&mailbox, &latest, 1);
    assert(muos_input_mailbox_begin_send(&mailbox, &latest) == 1);
    assert(latest.seq == 5 && latest.press_edges[1]);

    /* A failed JS delivery retries its edge instead of acknowledging it. */
    muos_input_mailbox_complete(&mailbox, &latest, 0);
    assert(muos_input_mailbox_begin_send(&mailbox, &latest) == 1);
    assert(latest.press_edges[1]);
    muos_input_mailbox_complete(&mailbox, &latest, 1);
    assert(muos_input_mailbox_begin_send(&mailbox, &latest) == 0);
    return 0;
}
