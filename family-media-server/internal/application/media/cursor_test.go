package media

import (
	"encoding/base64"
	"testing"
)

func TestOpaqueCursorRejectsUnknownFieldsAndTrailingValues(t *testing.T) {
	tests := []struct {
		name   string
		cursor string
	}{
		{
			name:   "unknown field",
			cursor: encodeOpaqueCursor(map[string]any{"scope": "scope", "offset": 1}),
		},
		{
			name:   "trailing value",
			cursor: base64.RawURLEncoding.EncodeToString([]byte(`{"scope":"scope"} {}`)),
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var decoded browseCursor
			if err := decodeOpaqueCursor(test.cursor, &decoded); err == nil {
				t.Fatal("expected strict cursor decoding to fail")
			}
		})
	}
}
