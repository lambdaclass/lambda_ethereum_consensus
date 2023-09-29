package p2p

import (
	"libp2p_port/internal/utils"
)

type Listener struct {
}

func NewListener(config *utils.Config) Listener {
	return Listener{}
}
