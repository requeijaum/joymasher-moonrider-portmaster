#ifndef MUOS_EXIT_COMBO_H
#define MUOS_EXIT_COMBO_H

#include <stdint.h>

#define MUOS_EXIT_COMBO_WINDOW_US INT64_C(2000000)

typedef struct {
    int was_down;
    int armed;
    int64_t first_press_us;
} muos_exit_combo_state;

/* Retorna 1 apenas na segunda borda MODE+START dentro da janela.
 * É obrigatório soltar ao menos um dos botões entre as duas bordas. */
static inline int muos_exit_combo_update(muos_exit_combo_state *s,
                                         int mode_down, int start_down,
                                         int64_t now_us) {
    int down = mode_down && start_down;
    if (s->armed && now_us - s->first_press_us > MUOS_EXIT_COMBO_WINDOW_US)
        s->armed = 0;

    int fire = 0;
    if (down && !s->was_down) {
        if (s->armed && now_us - s->first_press_us <= MUOS_EXIT_COMBO_WINDOW_US) {
            fire = 1;
            s->armed = 0;
        } else {
            s->armed = 1;
            s->first_press_us = now_us;
        }
    }
    s->was_down = down;
    return fire;
}

#endif
