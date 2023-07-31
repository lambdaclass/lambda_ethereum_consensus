#include "main.h"
#include "utils.h"
#include <erl_nif.h>

#define ERL_FUNCTION(FUNCTION_NAME) static ERL_NIF_TERM FUNCTION_NAME(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])

const uint64_t PID_LENGTH = 1024;

ERL_FUNCTION(hello)
{
    return enif_make_atom(env, "world");
}

ERL_FUNCTION(my_function)
{
    int a, b;
    enif_get_int(env, argv[0], &a);
    enif_get_int(env, argv[1], &b);

    int result = MyFunction(a, b);

    return enif_make_int(env, result);
}

ERL_FUNCTION(test_send_message)
{
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    if (!enif_self(env, pid))
    {
        return enif_make_atom(env, "error");
    }

    TestSendMessage(pid);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_new)
{
    int result = New(0, NULL);
    if (result == 0)
    {
        return enif_make_atom(env, "error");
    }
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_uint64(env, result));
}

ERL_FUNCTION(host_close)
{
    uintptr_t handle;
    enif_get_uint64(env, argv[0], &handle);

    HostClose(handle);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_set_stream_handler)
{
    uintptr_t handle;
    enif_get_uint64(env, argv[0], &handle);

    char proto_id[PID_LENGTH];
    enif_get_string(env, argv[1], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    // TODO: This is a memory leak.
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    if (!enif_self(env, pid))
    {
        return enif_make_atom(env, "error");
    }

    SetStreamHandler(handle, proto_id, (void *)pid);

    return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    {"hello", 0, hello},
    {"my_function", 2, my_function},
    {"test_send_message", 0, test_send_message},
    {"host_new", 0, host_new},
    {"host_close", 1, host_close},
    {"host_set_stream_handler", 2, host_set_stream_handler},
};

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, NULL, NULL, NULL, NULL)
