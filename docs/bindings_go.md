# Elixir ↔ Go bindings

## Introduction

The bindings are used to interact with the *go-libp2p* and *go-ethereum/p2p* libraries, in charge of peer-to-peer communication and discovery.
As we couldn't find a way to communicate the two languages directly, we used some **C** code to communicate the two sides.
However, as Go is a garbage-collected language, this brings some issues.

<!-- TODO: add an explanation about general bindings usage -->
<!-- TODO: explain the callback -> message translation -->

## References and handles

To manage memory, the Golang runtime tracks references (pointers) to find which objects are no longer used (more on this [here](https://tip.golang.org/doc/gc-guide)).
When those references are given to functions outside the Golang runtime (i.e. returned as a call result), they stop being valid (explained [here](https://pkg.go.dev/cmd/cgo#hdr-Passing_pointers)).
To bypass this restriction, we use [*handles*](https://pkg.go.dev/runtime/cgo).
Basically, they allow the reference to "live on" until we manually delete it.

This would allow us to pass references from Go to C and back:

```go
import "runtime/cgo"

// This comment exports the function
//export CreateArrayWithNumbers
func CreateArrayWithNumbers() C.uintptr_t {
    // This function is called from C
    var array []int
    for i := 0; i < 8; i++ {
        array = append(array, i)
    }
    // We create a handle for the array
    handle := cgo.NewHandle(array)
    // We turn it into a number before returning it to C
    return C.uintptr_t(handle)
}

//export SumAndConsumeArray
func SumAndConsumeArray(arrayHandle C.uintptr_t) uint {
    // We transform the number back to a handle
    handle := cgo.Handle(arrayHandle)
    // We retrieve the handle's contents
    array := handle.Value().([]int)
    // We use the array...
    var acc int
    for _, n := range array {
        acc = acc + n
    }
    // As we don't need the array anymore, we delete the handle to it
    handle.Delete()
    // After
    return acc
}
```

## Resources and destructors

What we have until now allows us to create long-living references, but we still need to free them manually (otherwise we leak memory).
To fix this, we can treat them as native objects with Erlang's [*Resource objects*](https://www.erlang.org/doc/man/erl_nif.html#functionality).
By treating them as resources with an associated type and destructor, we can let Erlang's garbage collector manage the reference's lifetime.
It works as follows:

<!-- TODO: add code examples -->

1. we declare a new resource type with [`enif_open_resource_type`](https://www.erlang.org/doc/man/erl_nif.html#enif_open_resource_type) when the NIF is loaded, passing its associated destructor
1. we create a new resource of that type with [`enif_alloc_resource`](https://www.erlang.org/doc/man/erl_nif#enif_alloc_resource)
1. we move that resource into an *environment* (i.e. the Erlang process that called the NIF) with [`enif_make_resource`](https://www.erlang.org/doc/man/erl_nif#enif_make_resource)
1. we release our local reference to that resource with [`enif_release_resource`](https://www.erlang.org/doc/man/erl_nif#enif_release_resource)
1. once all Elixir-side variables that reference the resource are out of scope, Erlang's garbage collector calls the destructor associated with the type

Note that we use a different resource type for each Go type. This allows us to differentiate between them, and return an error when an unexpected one is received.
