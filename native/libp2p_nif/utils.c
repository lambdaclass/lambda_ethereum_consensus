#include "utils.h"

void message_stream_handler(handler_send_message_t send_message, void *pid_bytes, uintptr_t stream)
{
    send_message(pid_bytes, stream);
}
