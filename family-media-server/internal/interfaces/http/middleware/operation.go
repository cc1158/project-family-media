package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"sync/atomic"
)

type operationIDKey struct{}

var fallbackOperationID atomic.Uint64

func Operation(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(r.Context(), operationIDKey{}, newOperationID())
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func OperationID(ctx context.Context) string {
	value, _ := ctx.Value(operationIDKey{}).(string)
	return value
}

func newOperationID() string {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err == nil {
		return hex.EncodeToString(bytes[:])
	}
	return "fallback-" + formatOperationSequence(fallbackOperationID.Add(1))
}

func formatOperationSequence(value uint64) string {
	const digits = "0123456789abcdef"
	var buffer [16]byte
	for index := len(buffer) - 1; index >= 0; index-- {
		buffer[index] = digits[value&0xf]
		value >>= 4
	}
	return string(buffer[:])
}
