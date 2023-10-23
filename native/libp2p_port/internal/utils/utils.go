package utils

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"math/big"

	"github.com/btcsuite/btcd/btcec/v2"
	gcrypto "github.com/ethereum/go-ethereum/crypto"
	"github.com/golang/snappy"
	pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/crypto"
)

func PanicIfError(err error) {
	if err != nil {
		panic(err)
	}
}

// Taken from Prysm: https://github.com/prysmaticlabs/prysm/blob/bcc23d2ded2548b6bce95680f49899325aedd960/crypto/ecdsa/utils.go
func ConvertFromInterfacePrivKey(privkey crypto.PrivKey) (*ecdsa.PrivateKey, error) {
	secpKey, ok := privkey.(*crypto.Secp256k1PrivateKey)
	if !ok {
		return nil, errors.New("could not cast to Secp256k1PrivateKey")
	}
	rawKey, err := secpKey.Raw()
	if err != nil {
		return nil, err
	}
	privKey := new(ecdsa.PrivateKey)
	k := new(big.Int).SetBytes(rawKey)
	privKey.D = k
	privKey.Curve = gcrypto.S256() // Temporary hack, so libp2p Secp256k1 is recognized as geth Secp256k1 in disc v5.1.
	privKey.X, privKey.Y = gcrypto.S256().ScalarBaseMult(rawKey)
	return privKey, nil
}

// Taken from Prysm: https://github.com/prysmaticlabs/prysm/blob/bcc23d2ded2548b6bce95680f49899325aedd960/crypto/ecdsa/utils.go
func ConvertToInterfacePubkey(pubkey *ecdsa.PublicKey) (crypto.PubKey, error) {
	xVal, yVal := new(btcec.FieldVal), new(btcec.FieldVal)
	if xVal.SetByteSlice(pubkey.X.Bytes()) {
		return nil, errors.New("X value overflows")
	}
	if yVal.SetByteSlice(pubkey.Y.Bytes()) {
		return nil, errors.New("Y value overflows")
	}
	newKey := crypto.PubKey((*crypto.Secp256k1PublicKey)(btcec.NewPublicKey(xVal, yVal)))
	// Zero out temporary values.
	xVal.Zero()
	yVal.Zero()
	return newKey, nil
}

// Only valid for post-Altair topics
func MsgID(msg *pb.Message) string {
	if msg == nil || msg.Data == nil || msg.Topic == nil {
		// Should never happen
		msg := make([]byte, 20)
		copy(msg, "invalid")
		return string(msg)
	}
	h := sha256.New()
	data, err := snappy.Decode(nil, msg.Data)
	if err != nil {
		// MESSAGE_DOMAIN_INVALID_SNAPPY
		h.Write([]byte{0, 0, 0, 0})
		data = msg.Data
	} else {
		// MESSAGE_DOMAIN_VALID_SNAPPY
		h.Write([]byte{1, 0, 0, 0})
	}
	var topicLen [8]byte
	binary.LittleEndian.PutUint64(topicLen[:], uint64(len(*msg.Topic)))
	h.Write(topicLen[:])
	h.Write([]byte(*msg.Topic))
	h.Write(data)
	var digest []byte
	digest = h.Sum(digest)
	return string(digest[:20])
}
