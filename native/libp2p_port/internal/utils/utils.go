package utils

type Config struct {
	ListenAddr []string
}

func PanicIfError(err error) {
	if err != nil {
		panic(err)
	}
}
