// Package credentials encrypts a node's access data for one registered device.
// It does not provision or revoke credentials on a VPN server.
package credentials

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strings"
)

const (
	domain       = "NONA-CREDENTIALS-v1"
	maxPlaintext = 4096
	maxEncoded   = 8192
)

type Context struct {
	AccountID string `json:"account_id"`
	DeviceID  string `json:"device_id"`
	NodeID    string `json:"node_id"`
	Version   uint64 `json:"version"`
}

func (c Context) aad() ([]byte, error) {
	for _, value := range []string{c.AccountID, c.DeviceID, c.NodeID} {
		if value == "" || len(value) > 256 || strings.ContainsRune(value, 0) {
			return nil, errors.New("invalid credential context")
		}
	}
	if c.Version == 0 {
		return nil, errors.New("invalid credential version")
	}
	return []byte(fmt.Sprintf("%s\x00%s\x00%s\x00%s\x00%d", domain, c.AccountID, c.DeviceID, c.NodeID, c.Version)), nil
}

func deriveKey(shared, aad []byte) ([]byte, error) {
	return hkdf.Key(sha256.New, shared, []byte(domain), string(aad), 32)
}

// Seal uses a fresh ephemeral X25519 key and AES-256-GCM nonce per call.
// The returned value is v1.ephemeral_public.nonce.ciphertext_with_tag.
func Seal(recipientPublic, plaintext []byte, context Context) (string, error) {
	return sealWith(recipientPublic, plaintext, context, rand.Reader)
}

func sealWith(recipientPublic, plaintext []byte, context Context, entropy io.Reader) (string, error) {
	aad, err := context.aad()
	if err != nil {
		return "", err
	}
	if len(plaintext) == 0 || len(plaintext) > maxPlaintext {
		return "", errors.New("invalid credential size")
	}
	recipient, err := ecdh.X25519().NewPublicKey(recipientPublic)
	if err != nil {
		return "", errors.New("invalid recipient key")
	}
	ephemeral, err := ecdh.X25519().GenerateKey(entropy)
	if err != nil {
		return "", err
	}
	shared, err := ephemeral.ECDH(recipient)
	if err != nil {
		return "", errors.New("invalid recipient key")
	}
	defer clear(shared)
	key, err := deriveKey(shared, aad)
	if err != nil {
		return "", err
	}
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(entropy, nonce); err != nil {
		return "", err
	}
	encode := base64.RawURLEncoding.EncodeToString
	return strings.Join([]string{"v1", encode(ephemeral.PublicKey().Bytes()), encode(nonce), encode(aead.Seal(nil, nonce, plaintext, aad))}, "."), nil
}

func parseEnvelope(encoded string) (publicBytes, nonce, ciphertext []byte, err error) {
	if len(encoded) > maxEncoded {
		return nil, nil, nil, errors.New("invalid credential envelope")
	}
	parts := strings.Split(encoded, ".")
	if len(parts) != 4 || parts[0] != "v1" {
		return nil, nil, nil, errors.New("invalid credential envelope")
	}
	decode := func(value string) ([]byte, error) {
		bytes, err := base64.RawURLEncoding.DecodeString(value)
		if err != nil || base64.RawURLEncoding.EncodeToString(bytes) != value {
			return nil, errors.New("invalid credential envelope")
		}
		return bytes, nil
	}
	publicBytes, err = decode(parts[1])
	if err != nil || len(publicBytes) != 32 {
		return nil, nil, nil, errors.New("invalid ephemeral key")
	}
	nonce, err = decode(parts[2])
	if err != nil || len(nonce) != 12 {
		return nil, nil, nil, errors.New("invalid credential nonce")
	}
	ciphertext, err = decode(parts[3])
	if err != nil || len(ciphertext) < 17 || len(ciphertext) > maxPlaintext+16 {
		return nil, nil, nil, errors.New("invalid credential ciphertext")
	}
	return publicBytes, nonce, ciphertext, nil
}

// ValidateEnvelope rejects plaintext or malformed data before it can enter a
// signed configuration. It does not prove that the recipient can decrypt it.
func ValidateEnvelope(encoded string) error {
	_, _, _, err := parseEnvelope(encoded)
	return err
}

// Open is useful for compatibility tests; clients use their platform library.
func Open(recipientPrivate []byte, encoded string, context Context) ([]byte, error) {
	aad, err := context.aad()
	if err != nil {
		return nil, err
	}
	publicBytes, nonce, ciphertext, err := parseEnvelope(encoded)
	if err != nil {
		return nil, err
	}
	private, err := ecdh.X25519().NewPrivateKey(recipientPrivate)
	if err != nil {
		return nil, errors.New("invalid device key")
	}
	public, err := ecdh.X25519().NewPublicKey(publicBytes)
	if err != nil {
		return nil, errors.New("invalid ephemeral key")
	}
	shared, err := private.ECDH(public)
	if err != nil {
		return nil, errors.New("invalid ephemeral key")
	}
	defer clear(shared)
	key, err := deriveKey(shared, aad)
	if err != nil {
		return nil, err
	}
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	plaintext, err := aead.Open(nil, nonce, ciphertext, aad)
	if err != nil {
		return nil, errors.New("credential authentication failed")
	}
	return plaintext, nil
}
