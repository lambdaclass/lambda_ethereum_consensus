#include "main.h"
#include "utils.h"
#include <erl_nif.h>

#define ERL_FUNCTION(FUNCTION_NAME) static ERL_NIF_TERM FUNCTION_NAME(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])

#define ERL_FUNCTION_GETTER(NAME, GETTER)                       \
    ERL_FUNCTION(NAME)                                          \
    {                                                           \
        uintptr_t _handle = get_handle_from_term(env, argv[0]); \
        OR_ERROR(_handle == 0, "invalid first argument");       \
        uintptr_t _res = GETTER(_handle);                       \
        return get_handle_result(env, _res);                    \
    }

#define OR_ERROR(COND, MSG)                \
    if (COND)                              \
    {                                      \
        return make_error_msg(env, (MSG)); \
    }

#define GET_HANDLE(TERM, NAME)                                 \
    ({                                                         \
        uintptr_t _handle = get_handle_from_term(env, (TERM)); \
        OR_ERROR(_handle == 0, "invalid " NAME);               \
        _handle;                                               \
    })

#define NIF_ENTRY(FUNCTION_NAME, ARITY)      \
    {                                        \
        #FUNCTION_NAME, ARITY, FUNCTION_NAME \
    }

const uint64_t PID_LENGTH = 1024;
const uint64_t BUFFER_SIZE = 4096;

/***********/
/* Helpers */
/***********/

static uintptr_t get_handle_from_term(ErlNifEnv *env, ERL_NIF_TERM term)
{
    uintptr_t handle;
    return enif_get_uint64(env, term, &handle) ? handle : 0;
}

static ERL_NIF_TERM make_error_msg(ErlNifEnv *env, const char *msg)
{
    return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_string(env, msg, ERL_NIF_UTF8));
}

static ERL_NIF_TERM make_ok_tuple2(ErlNifEnv *env, ERL_NIF_TERM term)
{
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), term);
}

static ERL_NIF_TERM get_handle_result(ErlNifEnv *env, uintptr_t handle)
{
    OR_ERROR(handle == 0, "invalid handle returned");
    return make_ok_tuple2(env, enif_make_uint64(env, handle));
}

/*********/
/* Utils */
/*********/

ERL_FUNCTION(listen_addr_strings)
{
    char addr_string[PID_LENGTH];
    uint64_t len = enif_get_string(env, argv[0], addr_string, PID_LENGTH, ERL_NIF_UTF8);
    OR_ERROR(len <= 0, "invalid string");

    uintptr_t handle = ListenAddrStrings(addr_string);

    return get_handle_result(env, handle);
}

/****************/
/* Host methods */
/****************/

ERL_FUNCTION(host_new)
{
    OR_ERROR(!enif_is_list(env, argv[0]), "options is not a list");
    const int MAX_OPTIONS = 256;
    uintptr_t options[MAX_OPTIONS];
    int i = 0;
    ERL_NIF_TERM head, tail = argv[0];
    while (!enif_is_empty_list(env, tail) && i < MAX_OPTIONS)
    {
        enif_get_list_cell(env, tail, &head, &tail);
        options[i++] = GET_HANDLE(head, "option");
    }
    GoSlice go_options = {options, i, MAX_OPTIONS};
    uintptr_t result = HostNew(go_options);
    return get_handle_result(env, result);
}

ERL_FUNCTION(host_close)
{
    uintptr_t host = GET_HANDLE(argv[0], "host");
    HostClose(host);
    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_set_stream_handler)
{
    uintptr_t host = GET_HANDLE(argv[0], "host");

    char proto_id[PID_LENGTH];
    uint64_t len = enif_get_string(env, argv[1], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    OR_ERROR(len <= 0, "invalid string");

    // TODO: This is a memory leak.
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    OR_ERROR(!enif_self(env, pid), "failed to get pid");

    SetStreamHandler(host, proto_id, (void *)pid);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_new_stream)
{
    uintptr_t host = GET_HANDLE(argv[0], "host");
    uintptr_t id = GET_HANDLE(argv[1], "peer id");

    char proto_id[PID_LENGTH];
    uint64_t len = enif_get_string(env, argv[2], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    OR_ERROR(len <= 0, "invalid string");

    int result = NewStream(host, id, proto_id);
    return get_handle_result(env, result);
}

ERL_FUNCTION_GETTER(host_peerstore, Peerstore)
ERL_FUNCTION_GETTER(host_id, ID)
ERL_FUNCTION_GETTER(host_addrs, Addrs)

/*********************/
/* Peerstore methods */
/*********************/

ERL_FUNCTION(peerstore_add_addrs)
{
    uintptr_t ps = GET_HANDLE(argv[0], "peerstore");
    uintptr_t id = GET_HANDLE(argv[1], "peer id");
    uintptr_t addrs = GET_HANDLE(argv[2], "addrs");
    u_long ttl;
    OR_ERROR(!enif_get_uint64(env, argv[3], &ttl), "invalid TTL");

    AddAddrs(ps, id, addrs, ttl);
    return enif_make_atom(env, "ok");
}

/******************/
/* Stream methods */
/******************/

ERL_FUNCTION(stream_read)
{
    uintptr_t stream = GET_HANDLE(argv[0], "stream");

    char buffer[BUFFER_SIZE];
    GoSlice go_buffer = {buffer, BUFFER_SIZE, BUFFER_SIZE};

    uint64_t read = StreamRead(stream, go_buffer);
    OR_ERROR(read == -1, "failed to read");

    return make_ok_tuple2(env, enif_make_string_len(env, buffer, read, ERL_NIF_UTF8));
}

ERL_FUNCTION(stream_write)
{
    uintptr_t stream = GET_HANDLE(argv[0], "stream");

    char data[BUFFER_SIZE];
    uint64_t len = enif_get_string(env, argv[1], data, BUFFER_SIZE, ERL_NIF_UTF8);
    OR_ERROR(len <= 0, "invalid string");

    GoSlice go_data = {data, len - 1, len - 1};

    uint64_t written = StreamWrite(stream, go_data);
    OR_ERROR(written == -1, "failed to write");

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(stream_close)
{
    uintptr_t stream = GET_HANDLE(argv[0], "stream");
    StreamClose(stream);
    return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    NIF_ENTRY(listen_addr_strings, 1),
    NIF_ENTRY(host_new, 1),
    NIF_ENTRY(host_close, 1),
    NIF_ENTRY(host_set_stream_handler, 2),
    NIF_ENTRY(host_new_stream, 3),
    NIF_ENTRY(host_peerstore, 1),
    NIF_ENTRY(host_id, 1),
    NIF_ENTRY(host_addrs, 1),
    NIF_ENTRY(peerstore_add_addrs, 4),
    NIF_ENTRY(stream_read, 1),
    NIF_ENTRY(stream_write, 2),
    NIF_ENTRY(stream_close, 1),
};

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, NULL, NULL, NULL, NULL)
