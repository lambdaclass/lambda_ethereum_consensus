package port

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"io"
	proto_defs "libp2p_port/internal/proto"
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

func (p *Port) readMessage(protoMsg proto.Message) error {
	msg, err := ReadDelimitedMessage(p.reader)
	if err == io.EOF {
		return err
	}
	utils.PanicIfError(err)

	err = proto.Unmarshal(msg, protoMsg)
	utils.PanicIfError(err)
	return err
}

func (p *Port) ReadInitArgs(initArgs *proto_defs.InitArgs) error {
	return p.readMessage(initArgs)
}

func (p *Port) ReadCommand(command *proto_defs.Command) error {
	return p.readMessage(command)
}

func (p *Port) sendMessage(protoMsg proto.Message) {
	data, err := proto.Marshal(protoMsg)
	utils.PanicIfError(err)

	var buf bytes.Buffer
	binary.Write(&buf, binary.BigEndian, uint32(len(data)))
	buf.Write(data)

	p.write_channel <- buf.Bytes()
}

func (p *Port) SendNotification(notification *proto_defs.Notification) {
	p.sendMessage(notification)
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
