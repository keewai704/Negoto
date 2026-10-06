// Minimal public interface of stb_vorbis (public domain, https://github.com/nothings/stb).
// Used to play Ogg Vorbis audio that AVFoundation can't decode.
#ifndef NEGOTO_STB_VORBIS_H
#define NEGOTO_STB_VORBIS_H

#ifdef __cplusplus
extern "C" {
#endif

/// Decodes a whole Ogg Vorbis stream into interleaved 16-bit PCM.
/// Returns the number of samples per channel, or -1 on failure. `*output` must be freed with free().
int stb_vorbis_decode_memory(const unsigned char *mem, int len, int *channels, int *sample_rate, short **output);

#ifdef __cplusplus
}
#endif

#endif
