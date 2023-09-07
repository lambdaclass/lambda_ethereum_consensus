#include "utils.h"

void run_callback(send_message_t send_message, void *pid_bytes, uintptr_t stream)
{
    send_message(pid_bytes, stream);
}
