#ifndef MUOS_INPUT_MAILBOX_H
#define MUOS_INPUT_MAILBOX_H

#include <stdint.h>

#define MUOS_INPUT_MAILBOX_BUTTONS 17
#define MUOS_INPUT_MAILBOX_AXES 4

typedef struct {
    float latest_buttons[MUOS_INPUT_MAILBOX_BUTTONS];
    float latest_axes[MUOS_INPUT_MAILBOX_AXES];
    float previous_buttons[MUOS_INPUT_MAILBOX_BUTTONS];
    uint64_t press_generation[MUOS_INPUT_MAILBOX_BUTTONS];
    uint64_t acked_press_generation[MUOS_INPUT_MAILBOX_BUTTONS];
    uint64_t latest_seq;
    int pending;
    int in_flight;
} muos_input_mailbox;

typedef struct {
    float buttons[MUOS_INPUT_MAILBOX_BUTTONS];
    float axes[MUOS_INPUT_MAILBOX_AXES];
    unsigned char press_edges[MUOS_INPUT_MAILBOX_BUTTONS];
    uint64_t press_generation[MUOS_INPUT_MAILBOX_BUTTONS];
    uint64_t seq;
} muos_input_snapshot;

void muos_input_mailbox_init(muos_input_mailbox *mailbox);
uint64_t muos_input_mailbox_update(muos_input_mailbox *mailbox,
                                   const float *buttons,
                                   const float *axes);
int muos_input_mailbox_begin_send(muos_input_mailbox *mailbox,
                                  muos_input_snapshot *snapshot);
void muos_input_mailbox_complete(muos_input_mailbox *mailbox,
                                 const muos_input_snapshot *snapshot,
                                 int delivered);

#endif
