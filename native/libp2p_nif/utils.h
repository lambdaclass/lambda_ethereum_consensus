#pragma once

#include <stdint.h> // for uintptr_t

// handler_send_message function signature.
typedef void (*handler_send_message_t)(void *pid_bytes, uintptr_t stream);

void message_stream_handler(handler_send_message_t send_message, void *pid_bytes, uintptr_t stream);
