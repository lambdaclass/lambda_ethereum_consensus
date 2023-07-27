#include <erl_nif.h>

extern int MyFunction(int a, int b);

extern int New();

static ERL_NIF_TERM hello(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    return enif_make_atom(env, "world");
}

static ERL_NIF_TERM my_function(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    int a, b;
    enif_get_int(env, argv[0], &a);
    enif_get_int(env, argv[1], &b);

    int result = MyFunction(a, b);

    return enif_make_int(env, result);
}

static ERL_NIF_TERM host_new(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    int result = New();
    if (result != 0)
    {
        return enif_make_atom(env, "error");
    }
    return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    {"hello", 0, hello},
    {"my_function", 2, my_function},
    {"host_new", 0, host_new},
};

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, NULL, NULL, NULL, NULL)
