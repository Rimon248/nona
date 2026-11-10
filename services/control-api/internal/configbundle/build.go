package configbundle

import (
	"bytes"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"io"
	"time"

	"nona.example/control-api/internal/credentials"
)

// PlainNode is provided by a trusted local provisioner after it has created
// credentials on the VPN node. Access must never be logged or stored as JSON.
type PlainNode struct {
	ID         string
	Provider   string
	Endpoint   string
	Transports []string
	Access     []byte
}

type accessDocument struct {
	SchemaVersion int `json:"schema_version"`
	VLESS         *struct {
		Host            string `json:"host"`
		Port            int    `json:"port"`
		UserID          string `json:"user_id"`
		ServerName      string `json:"server_name"`
		RealityPassword string `json:"reality_password"`
		ShortID         string `json:"short_id"`
		Flow            string `json:"flow"`
	} `json:"vless_reality"`
	Hysteria *struct {
		Host         string  `json:"host"`
		Port         int     `json:"port"`
		Auth         string  `json:"auth"`
		ServerName   string  `json:"server_name"`
		ObfsPassword *string `json:"obfs_password"`
	} `json:"hysteria2"`
}

func validateAccess(node PlainNode) error {
	if len(node.Access) == 0 || len(node.Access) > 4096 {
		return errors.New("invalid access document size")
	}
	var doc accessDocument
	decoder := json.NewDecoder(bytes.NewReader(node.Access))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&doc); err != nil || doc.SchemaVersion != 1 {
		return errors.New("invalid access document")
	}
	var trailing any
	if decoder.Decode(&trailing) != io.EOF {
		return errors.New("invalid access document")
	}
	declared := make(map[string]bool, len(node.Transports))
	for _, transport := range node.Transports {
		if declared[transport] || (transport != "vless-reality" && transport != "hysteria2") {
			return errors.New("invalid access transports")
		}
		declared[transport] = true
	}
	if len(declared) == 0 ||
		declared["vless-reality"] != (doc.VLESS != nil) ||
		declared["hysteria2"] != (doc.Hysteria != nil) ||
		(doc.VLESS != nil && doc.VLESS.Host != node.Endpoint) ||
		(doc.Hysteria != nil && doc.Hysteria.Host != node.Endpoint) ||
		(doc.VLESS != nil && (doc.VLESS.Port < 1 || doc.VLESS.Port > 65535 || doc.VLESS.UserID == "" || doc.VLESS.ServerName == "" || doc.VLESS.RealityPassword == "")) ||
		(doc.Hysteria != nil && (doc.Hysteria.Port < 1 || doc.Hysteria.Port > 65535 || doc.Hysteria.Auth == "" || doc.Hysteria.ServerName == "")) {
		return errors.New("access metadata mismatch")
	}
	return nil
}

// BuildForDevice encrypts each node's access for one registered device and
// signs the resulting update. It does not create credentials on a VPN server.
func BuildForDevice(accountID, deviceID string, devicePublic []byte, version, rulesVersion uint64,
	issuedAt, expiresAt time.Time, nodes []PlainNode, keyID string, signer ed25519.PrivateKey) (Envelope, error) {
	sealed := make([]Node, 0, len(nodes))
	for _, node := range nodes {
		if err := validateAccess(node); err != nil {
			return Envelope{}, err
		}
		ciphertext, err := credentials.Seal(devicePublic, node.Access, credentials.Context{
			AccountID: accountID, DeviceID: deviceID, NodeID: node.ID, Version: version,
		})
		if err != nil {
			return Envelope{}, err
		}
		sealed = append(sealed, Node{
			ID: node.ID, Provider: node.Provider, Endpoint: node.Endpoint,
			Transports: node.Transports, EncryptedCredentials: ciphertext,
		})
	}
	return Sign(NewPayload(accountID, deviceID, version, rulesVersion, issuedAt, expiresAt, sealed), keyID, signer)
}
