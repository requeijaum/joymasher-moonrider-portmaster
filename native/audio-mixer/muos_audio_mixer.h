/* muos_audio_mixer.h — non-blocking native audio service API. */
#ifndef MUOS_AUDIO_MIXER_H
#define MUOS_AUDIO_MIXER_H

#include "audio_worker.h"

int muos_mixer_init(void);
int muos_mixer_play(int id, const char *path, int loop, float volume);
int muos_mixer_play_pair(int intro_id, int loop_id, const char *intro_path,
                         const char *loop_path, unsigned int intro_ms, float volume);
int muos_mixer_stop(int id);
int muos_mixer_volume(int id, float volume);
int muos_mixer_pause(int id, int paused);
void muos_mixer_stop_all(void);
void muos_mixer_reap(void);
void muos_mixer_get_stats(muos_audio_worker_stats *stats);
void muos_mixer_shutdown(void);

#endif
