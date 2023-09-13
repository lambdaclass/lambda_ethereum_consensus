package port

import (
	"bufio"
	"encoding/binary"
	"io"
	libp2p "libp2p_port/internal/proto"
	"libp2p_port/internal/utils"
	"os"

	"google.golang.org/protobuf/proto"
)

func ReadCommand(reader *bufio.Reader, command *libp2p.Command) error {
	msg, err := ReadDelimitedMessage(reader)
	if err == io.EOF {
		return err
	}
	utils.PanicIfError(err)

	err = proto.Unmarshal(msg, command)
	utils.PanicIfError(err)
	return err
}

func ReadDelimitedMessage(r io.Reader) ([]byte, error) {
	// 1. Read the fixed-size length prefix (4 bytes for a uint32).
	var length uint32
	err := binary.Read(r, binary.BigEndian, &length)
	if err != nil {
		return nil, err
	}

	// 2. Read the protobuf message of the given length.
	data := make([]byte, length)
	_, err = io.ReadFull(r, data)
	if err != nil {
		return nil, err
	}

	return data, nil
}

func SendNotification(notification *libp2p.Notification) {
	data, err := proto.Marshal(notification)
	utils.PanicIfError(err)

	os.Stdout.Write(data)
}
