/* muos_audio_mixer.h — API do mixer nativo (impl em muos_audio_mixer.c) */
#ifndef MUOS_AUDIO_MIXER_H
#define MUOS_AUDIO_MIXER_H
int  muos_mixer_init(void);
int  muos_mixer_play(int id, const char* path, int loop, float volume);
int  muos_mixer_play_pair(int intro_id, int loop_id, const char* intro_path,
                          const char* loop_path, unsigned int intro_ms, float volume);
int  muos_mixer_stop(int id);
int  muos_mixer_volume(int id, float v);
int  muos_mixer_pause(int id, int paused);
void muos_mixer_stop_all(void);
void muos_mixer_reap(void);
void muos_mixer_shutdown(void);
#endif
