#include "utils.h"
#include <erl_nif.h>

ErlNifPid *get_pid(erl_pid_t _pid)
{
    return (ErlNifPid *)_pid;
}

void send_message(erl_pid_t _pid, uintptr_t stream_handle)
{
    // Passed as void* to avoid including erl_nif.h in the header.
    ErlNifPid *pid = get_pid(_pid);
    ErlNifEnv *env = enif_alloc_env();

    ERL_NIF_TERM message = enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_uint64(env, stream_handle));

    int result = enif_send(NULL, pid, env, message);
    // On error, the env isn't freed by the function.
    if (!result)
    {
        enif_free_env(env);
    }
}

void go_test_send_message(erl_pid_t _pid)
{
    // Passed as void* to avoid including erl_nif.h in the header.
    ErlNifPid *pid = get_pid(_pid);
    ErlNifEnv *env = enif_alloc_env();

    ERL_NIF_TERM message = enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_uint64(env, 5353));

    int result = enif_send(NULL, pid, env, message);
    // On error, the env isn't freed by the function.
    if (!result)
    {
        enif_free_env(env);
    }
    free(pid);
}
