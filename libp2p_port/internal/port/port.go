package port

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"io"
	libp2p "libp2p_port/internal/proto"
	"libp2p_port/internal/utils"
	"os"

	"google.golang.org/protobuf/proto"
)

type Port struct {
	reader        *bufio.Reader
	write_channel chan []byte
}

func NewPort() *Port {
	port := &Port{reader: bufio.NewReader(os.Stdin), write_channel: make(chan []byte, 100)}
	go WriteBytes(port.write_channel)
	return port
}

func WriteBytes(write_channel chan []byte) {
	for {
		bytes_to_write := <-write_channel
		os.Stdout.Write(bytes_to_write)
		os.Stdout.Sync()
	}
}

func (p *Port) ReadCommand(command *libp2p.Command) error {
	msg, err := ReadDelimitedMessage(p.reader)
	if err == io.EOF {
		return err
	}
	utils.PanicIfError(err)

	err = proto.Unmarshal(msg, command)
	utils.PanicIfError(err)
	return err
}

func (p *Port) SendNotification(notification *libp2p.Notification) {
	data, err := proto.Marshal(notification)
	utils.PanicIfError(err)

	var buf bytes.Buffer
	binary.Write(&buf, binary.BigEndian, uint32(len(data)))
	buf.Write(data)

	p.write_channel <- buf.Bytes()
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
