#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"


#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>

#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"


#include <rtl-sdr.h>



struct rtlsdr_context {
  rtlsdr_dev_t* device;
  pthread_t read_thread;

  int signalling_fd;
  void *buffer;
  uint64_t buffer_size;
};


static int number_of_rtlsdr_inits = 0;

static volatile sig_atomic_t terminate_callback = 0;


static void _rx_callback(unsigned char *buf, uint32_t len, void *void_ctx) {
  struct rtlsdr_context *ctx = void_ctx;
  char junk = '\x00';
  ssize_t result;

  if (terminate_callback) {
    terminate_callback = 0;
    result = write(ctx->signalling_fd, &junk, 1);
    if (result != 1) abort();
    return;
  }

  ctx->buffer_size = (size_t)len;
  ctx->buffer = buf;

  result = write(ctx->signalling_fd, &junk, 1);
  if (result != 1) abort();
  result = read(ctx->signalling_fd, &junk, 1);
  if (result != 1) abort();
}


static void *read_thread_function(void *void_ctx) {
  struct rtlsdr_context *ctx = void_ctx;
  rtlsdr_read_async(ctx->device, _rx_callback, ctx, 0, 0);
  return 0;
}






MODULE = Radio::RTLSDR         PACKAGE = Radio::RTLSDR
PROTOTYPES: ENABLE


BOOT:
  PERL_MATH_INT64_LOAD_OR_CROAK;




struct rtlsdr_context *
new_context()
    CODE:
        int result;
        struct rtlsdr_context *ctx;
        uint32_t device_index = 0; // FIXME: let this be selectable

        ctx = malloc(sizeof(struct rtlsdr_context));

        result = rtlsdr_open(&ctx->device, device_index);

        if (result < 0) {
          free(ctx);
          croak("rtlsdr_open() failed to open device %d\n", device_index);
        }

        number_of_rtlsdr_inits++;

        RETVAL = ctx;

    OUTPUT:
        RETVAL



void
_set_signalling_fd(ctx, fd)
        struct rtlsdr_context *ctx
        int fd
    CODE:
        ctx->signalling_fd = fd;



uint64_t
_get_buffer_size(ctx)
        struct rtlsdr_context *ctx
    CODE:
        RETVAL = ctx->buffer_size;

    OUTPUT:
        RETVAL




SV *
_copy_from_buffer(ctx)
        struct rtlsdr_context *ctx
    CODE:
        SV *output;
        char *outputp;

        output = newSVpvn("", 0);
        SvGROW(output, ctx->buffer_size);
        SvCUR_set(output, ctx->buffer_size);
        outputp = SvPV(output, ctx->buffer_size);

        memcpy(outputp, ctx->buffer, ctx->buffer_size);

        RETVAL = output;

    OUTPUT:
        RETVAL



void
_start_rx(ctx)
        struct rtlsdr_context *ctx
    CODE:
        int result;
        int gain;

        result = rtlsdr_set_tuner_gain_mode(ctx->device, 1);
        result |= rtlsdr_set_tuner_gain(ctx->device, 450);

        if (result < 0) {
          croak("_start_rx() failed to set gain");
        }

        result = rtlsdr_reset_buffer(ctx->device);
        if (result < 0) {
          croak("_start_rx() failed to reset buffers");
        }

        pthread_create(&ctx->read_thread, NULL, read_thread_function, (void *)ctx);


void _set_terminate_callback_flag(ctx)
        struct rtlsdr_context *ctx
    CODE:
        terminate_callback = 1;



void _stop_rx(ctx)
        struct rtlsdr_context *ctx
    CODE:
        int result;

        result = rtlsdr_cancel_async(ctx->device);

        if (result < 0) {
          croak("_stop_rx() rtlsdr_cancel_async failed");
        }


void
_set_freq(ctx, freq)
        struct rtlsdr_context *ctx
        uint64_t freq
    CODE:
        int result;

        if (freq >= 1ll<<32) {
          croak("_set_freq() frequency outside RTL-SDR's API range");
        }

        result = rtlsdr_set_center_freq(ctx->device, freq);

        if (result < 0) {
          croak("_set_freq() rtlsdr_set_center_freq failed for frequency %" PRId64, freq);
        }


void
_set_sample_rate(ctx, sample_rate)
        struct rtlsdr_context *ctx
        unsigned int sample_rate
    CODE:
        int result;

        result = rtlsdr_set_sample_rate(ctx->device, sample_rate);

        if (result < 0) {
          croak("_set_sample_rate() rtlsdr_set_sample_rate failed");
        }
