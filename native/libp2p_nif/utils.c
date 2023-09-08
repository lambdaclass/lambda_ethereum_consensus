#include "utils.h"

bool run_callback1(send_message1_t send_message, void *pid_bytes, uintptr_t stream)
{
    return send_message(pid_bytes, stream);
}
