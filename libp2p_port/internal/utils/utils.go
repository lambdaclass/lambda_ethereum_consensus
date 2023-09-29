package utils

type Config struct {
	ListenAddress []string
}

func PanicIfError(err error) {
	if err != nil {
		panic(err)
	}
}
