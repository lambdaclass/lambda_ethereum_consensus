// NOTE: the package **must** be named main
package main

import "C"

//export MyFunction
func MyFunction(a, b int) int {
	return a + 2*b
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
